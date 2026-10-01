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
  void setHidden(bool hidden) {
    if (_hidden == hidden) return;
    _hidden = hidden;
    if (hidden) {
      _sendStatus(AppConfig.statusOffline);
    } else {
      // 令牌可能已经过期（后台放久了），重连时会重新登录。
      AuthService.clear();
      if (_channel == null) {
        connect();
      } else {
        updateStatus(_lastStatus);
      }
    }
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
