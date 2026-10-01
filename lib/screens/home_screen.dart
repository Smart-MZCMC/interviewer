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
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  String _currentStatus = AppConfig.statusNotReady;
  bool _isConnected = false;

/// 当前正在播送的机位。握手时的项目状态打底，之后由 shot_state 实时刷新。
  ///
  /// 记者需要知道现在画面在哪个机位——它决定了自己该不该出现在镜头里。
  /// 这个值以前是拿不到的：切台状态只在新的 shot_state 到来时广播一次，
  /// 采访端中途连上或重连后完全不知道当前在播什么。
  String _currentShot = '';

  /// 本次要切过去的机位；空串表示没有预告。
  ///
  /// 与「正在播送」分开显示，是因为两者的行动含义不同：正在播送说明
  /// 「你已经在镜头里了」，预告说明「准备一下，马上到你」。
  String _nextShot = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectionSubscription = _wsService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
      }
    });
    _messageSubscription = _wsService.messageStream.listen(_onMessage);
    _wsService.connect();
  }

  void _onMessage(Map<String, dynamic> msg) {
    final type = msg['type'];
    final payload = msg['payload'];

    if (type == 'shot_state') {
      // 导播每次切台都会广播一份完整状态（当前 + 预告）。
      //
      // 之前只认握手时的 system 消息，于是这一整段直播期间显示的机位一直
      // 是刚连上那一刻的值——切了台屏幕也不变，记者照着旧机位准备。
      if (payload is! Map) return;
      // 自己不上报 shot_state，但仍然按服务端给的权威值显示，不做本地推断。
      final current = (payload['current'] ?? '') as String;
      final next = (payload['next'] ?? '') as String;
      if (current == _currentShot && next == _nextShot) return;
      if (!mounted) return;
      setState(() {
        _currentShot = current;
        _nextShot = next;
      });
      return;
    }

    if (type != 'system') return;
    if (payload is! Map) return;
    if (payload['state_available'] != true) return;
    final current = (payload['current_shot'] ?? '') as String;
    if (!mounted) return;
    setState(() {
      _currentShot = current;
      // 握手消息不带预告，清掉上一次残留：重连后不能继续显示早已过去的预告。
      _nextShot = '';
    });
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
    _messageSubscription?.cancel();
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
            // 顶部：采访点名称 + 当前播送机位
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              color: Colors.grey.shade900,
              child: Column(
                children: [
                  Text(
                    AppConfig.pointName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
const SizedBox(height: 6),
                  Text(
                    // 没有当前机位时不要编一个，直接说明还没开始。
                    _currentShot.isEmpty ? '等待导播切台' : '正在播送：$_currentShot',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _currentShot.isEmpty
                          ? Colors.white.withValues(alpha: 0.45)
                          : Colors.lightGreenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // 预告单独一行。跟「正在播送」挤在一行时两个信息会互相
                  // 抢注意力，而它们要回答的是两个不同问题：
                  // 现在镜头在哪（要不要动）、马上要切到哪（要不要准备）。
                  if (_nextShot.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '即将切到：$_nextShot',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
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
