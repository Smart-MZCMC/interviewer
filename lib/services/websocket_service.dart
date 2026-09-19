import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _statusSyncTimer;
  bool _intentionalClose = false;
  bool _connecting = false; // 防止重复连接
  int _reconnectAttempts = 0;
  String _lastStatus = 'not_ready';

  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isConnected => _channel != null && _connecting == false;

  void connect() {
    if (_connecting || _channel != null) return; // 防止重复连接
    _intentionalClose = false;
    _doConnect();
  }

  void _doConnect() {
    if (_connecting) return;
    _connecting = true;
    try {
      final wsUri = Uri.parse(
        '${AppConfig.wsUrl}?project_id=${AppConfig.projectId}&role=interviewer&point_code=${AppConfig.pointCode}',
      );
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
          if (!_intentionalClose) {
            _scheduleReconnect();
          }
        },
        onError: (error) {
          _connecting = false;
          _connectionController.add(false);
          _channel = null;
          if (!_intentionalClose) {
            _scheduleReconnect();
          }
        },
      );

      _startHeartbeat();
      // 连接成功后发送当前状态
      _statusSyncTimer?.cancel();
      _statusSyncTimer = Timer(const Duration(milliseconds: 500), () {
        if (_channel != null) {
          updateStatus(_lastStatus);
        }
      });
    } catch (e) {
      _connecting = false;
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'chat',
          'project_id': AppConfig.projectId,
          'payload': {'message': 'heartbeat'},
        }));
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectAttempts++;
    final delay = Duration(seconds: (1 * (1 << (_reconnectAttempts - 1))).clamp(1, 10));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _doConnect);
  }

  void updateStatus(String status) {
    _lastStatus = status;
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'interview_status',
      'project_id': AppConfig.projectId,
      'payload': {
        'point_code': AppConfig.pointCode,
        'point_name': AppConfig.pointName,
        'status': status,
      },
    }));
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
