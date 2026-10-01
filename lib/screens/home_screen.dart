import 'dart:async';
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/websocket_service.dart';
import '../widgets/version_banner.dart';

class HomeScreen extends StatefulWidget {
  /// 注入 WebSocket 服务，**仅用于测试**。
  ///
  /// 真实连接会发起网络请求并在失败时留下重连 Timer，widget test 结束后
  /// 会被 "A Timer is still pending" 断言拦下。所以测试要传一个
  /// connect() 被覆盖成空实现的假对象。
  final WebSocketService? service;

  const HomeScreen({super.key, this.service});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // late final 才能在初始化器里读 widget。
  late final WebSocketService _wsService = widget.service ?? WebSocketService();
  StreamSubscription<bool>? _connectionSubscription;
  String _currentStatus = AppConfig.statusNotReady;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectionSubscription = _wsService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
      }
    });
    _wsService.connect();
  }

  /// 页面切到后台 / 回到前台。
  ///
  /// 这不是「可选的优化」：记者把浏览器切走或锁屏后，WebSocket 往往还开着，
  /// 服务端只靠 TCP 超时判断掉线要等很久，而导播端在这段时间里一直显示
  /// 绿色「就绪」。所以在进入后台时主动上报 offline。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _wsService.setHidden(state != AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionSubscription?.cancel();
    _wsService.dispose();
    super.dispose();
  }

  Color _getStatusColor() {
    switch (_currentStatus) {
      case AppConfig.statusReady:
        return Colors.green;
      case AppConfig.statusPreparing:
        return Colors.blue;
      case AppConfig.statusNotReady:
        return Colors.grey;
      default:
        return Colors.red.shade300;
    }
  }

  String _getStatusText() {
    switch (_currentStatus) {
      case AppConfig.statusReady:
        return '就绪';
      case AppConfig.statusPreparing:
        return '准备中';
      case AppConfig.statusNotReady:
        return '未就绪';
      default:
        return '离线';
    }
  }

  void _cycleStatus() {
    final statuses = [
      AppConfig.statusNotReady,
      AppConfig.statusPreparing,
      AppConfig.statusReady,
    ];
    final currentIndex = statuses.indexOf(_currentStatus);
    final nextIndex = (currentIndex + 1) % statuses.length;
    final nextStatus = statuses[nextIndex];

    setState(() => _currentStatus = nextStatus);
    _wsService.updateStatus(nextStatus);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 版本提示。低于最低适配版本时部分功能会异常，采访员该在按下
            // 状态键之前就看到，而不是等播送中断才发现客户端太旧。
            VersionBanner(serverUrl: AppConfig.serverUrl),
            // 顶部：采访点名称
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              color: Colors.grey.shade900,
              child: Text(
                AppConfig.pointName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // 中间：巨大状态按钮
            Expanded(
              child: GestureDetector(
                onTap: _cycleStatus,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _getStatusColor(),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _getStatusColor().withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _currentStatus == AppConfig.statusReady
                              ? Icons.check_circle
                              : _currentStatus == AppConfig.statusPreparing
                                  ? Icons.hourglass_top
                                  : Icons.cancel,
                          size: 80,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _getStatusText(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '点击切换状态',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 底部：连接状态
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.grey.shade900,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isConnected ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isConnected ? '已连接' : '连接中...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
