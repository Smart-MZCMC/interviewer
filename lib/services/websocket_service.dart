import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import 'auth_service.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _statusSyncTimer;
  bool _intentionalClose = false;
  bool _connecting = false; // 防止重复连接
  int _reconnectAttempts = 0;
  String _lastStatus = AppConfig.statusNotReady;

  /// 页面是否处于后台。
  ///
  /// 进入后台时会主动上报 offline：记者把浏览器切走、锁屏或系统回收标签页
  /// 时，WebSocket 往往还「开着」，服务端的 TCP 要等很久才报错。没有这一条，
  /// 导播端会一直显示绿色「就绪」，而人其实已经离开。
  bool _hidden = false;

  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isConnected => _channel != null && _connecting == false;

  void connect() {
    if (_connecting || _channel != null) return; // 防止重复连接
    _intentionalClose = false;
    unawaited(_doConnect());
  }

  Future<void> _doConnect() async {
    if (_connecting) return;
    _connecting = true;

    // 先换令牌再建连。后端开启项目成员校验后，没有令牌会在握手阶段被 403，
    // 而握手失败在客户端只表现为「连接不上」，现场根本看不出是凭据问题。
    final token = await AuthService.ensureToken();

    try {
      var url = '${AppConfig.wsUrl}?project_id=${AppConfig.projectId}'
          '&role=interviewer&point_code=${AppConfig.pointCode}';
      if (token != null && token.isNotEmpty) {
        url += '&token=${Uri.encodeQueryComponent(token)}';
      }
      final wsUri = Uri.parse(url);
      _channel = WebSocketChannel.connect(wsUri);

      _channel!.stream.listen(
        (data) {
          _reconnectAttempts = 0;
          _connectionController.add(true);
          final msg = jsonDecode(data.toString());
          _messageController.add(msg);
        },
        onDone: () {
          _connecting = false;
          _connectionController.add(false);
          _channel = null;
          _rejectTokenIfUnauthorized();
          _reconnectTimer?.cancel();
          if (!_intentionalClose) {
            // 连接断了就没法再用 WebSocket 通知服务端，改走 HTTP。
            // 这条请求正是「记者走出 WiFi」时唯一还能到达服务端的东西。
            unawaited(_postStatus(AppConfig.statusOffline));
            _scheduleReconnect();
          }
        },
        onError: (error) {
          _connecting = false;
          _connectionController.add(false);
          _channel = null;
          _rejectTokenIfUnauthorized();
          if (!_intentionalClose) {
            unawaited(_postStatus(AppConfig.statusOffline));
            _scheduleReconnect();
          }
        },
      );

      _startHeartbeat();
      // 连接成功后发送当前状态
      _statusSyncTimer?.cancel();
      _statusSyncTimer = Timer(const Duration(milliseconds: 500), () {
        // 页面在后台时不要把自己的状态改回「就绪」——那正好抵消掉
        // 刚才上报的 offline。
        if (_channel != null && !_hidden) {
          updateStatus(_lastStatus);
        }
      });
    } catch (e) {
      _connecting = false;
      _scheduleReconnect();
    }
  }

  /// 保活心跳。
  ///
  /// 载荷里带一个时间戳，服务端据此刷新 Client.LastSeen——掉线扫描判断的
  /// 就是「多久没收到这个客户端的任何消息」。心跳载荷里的其他字段服务端
  /// 不解析（IsHeartbeat 只看 `message == "heartbeat"`），所以状态仍然由
  /// interview_status 单独上报，不在这里夹带。
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'chat',
          'project_id': AppConfig.projectId,
          'payload': {
            'message': 'heartbeat',
            'ts': DateTime.now().millisecondsSinceEpoch,
          },
        }));
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectAttempts++;
    final delay = Duration(seconds: (1 * (1 << (_reconnectAttempts - 1))).clamp(1, 10));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => unawaited(_doConnect()));
  }

  /// 页面可见性变化。
  ///
  /// 进入后台时上报 offline；回到前台时把用户选定的状态再报一次，
  /// 否则导播端会一直停在红色「离线」上。
  ///
  /// 这里**不碰登录令牌**。此前回到前台会调一次 `AuthService.clear()`，
  /// 于是每次切走再切回来都要重新登录一轮——而令牌多半根本没过期。
  /// 「切后台」不是「凭据被拒」，真正的拒绝只有握手 401 那一种，
  /// 由 [_rejectTokenIfUnauthorized] 处理。
  void setHidden(bool hidden) {
    if (_hidden == hidden) return;
    _hidden = hidden;
    if (hidden) {
      _sendStatus(AppConfig.statusOffline);
    } else {
      if (_channel == null) {
        connect();
      } else {
        updateStatus(_lastStatus);
      }
    }
  }

  /// 握手被 401 拒绝时丢掉本地令牌，让下一轮 ensureToken 重新登录。
  ///
  /// 浏览器端的 WebSocket 不会把 HTTP 状态码交给 JS，`error` 事件的类型是
  /// `'WebSocketNetworkError'`，拿不到 401。所以只能在**没收到欢迎消息**
  /// 时判定：能连上就说明握手过了，收不到就是没过。真正的 403（不是项目成员）
  /// 会先在服务端打日志，这里不区分，一律当作需要换一个新令牌。
  ///
  /// 关键是不能对每一次握手失败都清令牌：网络抖动、后端重启期间都会失败，
  /// 那时清掉令牌只会让重连永远拿不到凭据。判据必须是「令牌被拒」，
  /// 而 welcome 消息是握手成功的唯一确证。
  void _rejectTokenIfUnauthorized() {
    if (_channel != null) return;
    if (AuthService.token == null) return;
    debugPrint('[Auth] 握手未收到欢迎消息，令牌可能已失效');
    AuthService.clear();
  }

  void updateStatus(String status) {
    _lastStatus = status;
    _sendStatus(status);
  }

  /// 优先走 WebSocket，通道不可用时退回 HTTP。
  ///
  /// 两条路径服务端都会既落库又广播（见 app/ws/hub.go 与
  /// app/http/controllers/interview_controller.go），所以不必担心某一条
  /// 只改了一半。
  void _sendStatus(String status) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'interview_status',
        'project_id': AppConfig.projectId,
        'payload': {
          'point_code': AppConfig.pointCode,
          'point_name': AppConfig.pointName,
          'status': status,
        },
      }));
      return;
    }
    unawaited(_postStatus(status));
  }

  /// 用 HTTP 上报状态。WebSocket 断开时这是唯一还能到达服务端的方式。
  Future<void> _postStatus(String status) async {
    if (AppConfig.pointCode.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('${AppConfig.serverUrl}/api/interview/status'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'project_id': AppConfig.projectId,
              'point_code': AppConfig.pointCode,
              'point_name': AppConfig.pointName,
              'status': status,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      // 断网时这条请求必然失败，这正是「已经掉线」本身，不值得刷屏。
      debugPrint('[WS] 离线状态上报失败（大概率就是断网）: $e');
    }
  }

  void disconnect() {
    _intentionalClose = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _statusSyncTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connecting = false;
  }

  void dispose() {
    disconnect();
    _connectionController.close();
    _messageController.close();
  }
}
