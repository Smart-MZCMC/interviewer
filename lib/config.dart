class AppConfig {
  // 服务器地址 - 根据实际部署修改
  static const String serverUrl = 'http://127.0.0.1:3000';
  static const String wsUrl = 'ws://127.0.0.1:3002/ws';

  // 采访点配置 - 启动时写死
  static const int projectId = 1;
  static const String pointCode = 'point_1';
  static const String pointName = '采访点 1';

  // 状态枚举
  static const String statusReady = 'ready';
  static const String statusPreparing = 'preparing';
  static const String statusNotReady = 'not_ready';
  static const String statusOffline = 'offline';
}
