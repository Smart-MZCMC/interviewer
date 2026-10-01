// 采访端界面冒烟测试。
//
// 关键点：必须注入假的 WebSocketService。真实连接会发网络请求，
// 失败后还会挂重连 Timer，widget test 结束时会被
// "A Timer is still pending even after the widget tree was disposed" 断言拦下。
// 注入假对象之后，这个测试不依赖任何真实服务器——换服务器地址不会让它变红。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interviewer/config.dart';
import 'package:interviewer/screens/home_screen.dart';
import 'package:interviewer/services/websocket_service.dart';

/// 不做任何网络连接的假服务。
class _FakeWsService extends WebSocketService {
  @override
  void connect() {}
}

/// 能主动往界面推消息的假服务，用来验证实时切台状态的处理。
///
/// 直接复用真实的 [messageStream]，所以走的是 HomeScreen 里真正的
/// _onMessage，而不是另写一条测试专用通路——那样测的就不是线上代码了。
class _PushableWsService extends WebSocketService {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get messageStream => _controller.stream;

  @override
  void connect() {}

  void push(Map<String, dynamic> message) => _controller.add(message);
}

/// 推完消息后排空队列再断言。
///
/// 消息经 StreamController.broadcast 异步送达，setState 落在微任务里；
/// 单次 pump() 建帧时它还没跑完，界面上就表现为「消息收到了但没反应」。
Future<void> deliver(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

Widget _app() => MaterialApp(home: HomeScreen(service: _FakeWsService()));

void main() {
  testWidgets('显示默认采访点与未就绪状态，点击后切到准备中', (WidgetTester tester) async {
    await tester.pumpWidget(_app());

    expect(find.text('采访点 1'), findsOneWidget);
    expect(find.text('未就绪'), findsOneWidget);
    expect(find.text('点击切换状态'), findsOneWidget);

    await tester.tap(find.text('未就绪'));
    await tester.pump();

    expect(find.text('准备中'), findsOneWidget);
    expect(find.text('未就绪'), findsNothing);
  });

  // 回归：采访端此前只认握手时的 system 消息，切台广播 shot_state 被直接丢掉，
  // 于是整个直播期间屏幕上的机位一直停在刚连上那一刻的值——切了台也不变。
  testWidgets('收到 shot_state 时实时更新正在播送的机位', (WidgetTester tester) async {
    final service = _PushableWsService();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(service: service)));
    await tester.pump();

    // 还没连上时不要编一个机位出来。
    expect(find.text('等待导播切台'), findsOneWidget);

    service.push({
      'type': 'system',
      'payload': {'state_available': true, 'current_shot': '1000米'}
    });
    await deliver(tester);
    expect(find.text('正在播送：1000米'), findsOneWidget);

    service.push({
      'type': 'shot_state',
      'payload': {'current': '跳远', 'next': '1000米'}
    });
    await deliver(tester);
    expect(find.text('正在播送：跳远'), findsOneWidget);
    expect(find.text('即将切到：1000米'), findsOneWidget);

    // 切走之后预告要清掉，否则屏幕上会一直挂着早已过去的预告。
    service.push({
      'type': 'shot_state',
      'payload': {'current': '1000米', 'next': ''}
    });
    await deliver(tester);
    expect(find.text('正在播送：1000米'), findsOneWidget);
    expect(find.text('即将切到：1000米'), findsNothing);
  });

  // 握手消息不带预告，所以重连时必须把上一次残留的预告清掉。
  testWidgets('重连后的握手消息清掉上一次残留的预告', (WidgetTester tester) async {
    final service = _PushableWsService();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(service: service)));
    await tester.pump();

    service.push({
      'type': 'shot_state',
      'payload': {'current': '跳远', 'next': '1000米'}
    });
    await deliver(tester);
    expect(find.text('即将切到：1000米'), findsOneWidget);

    service.push({
      'type': 'system',
      'payload': {'state_available': true, 'current_shot': '跳高'}
    });
    await deliver(tester);
    expect(find.text('正在播送：跳高'), findsOneWidget);
    expect(find.text('即将切到：1000米'), findsNothing);
  });

  test('applyRuntimeConfig 逐字段校验，非法值不覆盖默认值', () {
    // 缺字段 / 类型不对 / 空串，都应保留默认值
    AppConfig.applyRuntimeConfig(<String, dynamic>{});
    expect(AppConfig.wsUrl, AppConfig.defaultWsUrl);
    expect(AppConfig.projectId, AppConfig.defaultProjectId);

    AppConfig.applyRuntimeConfig(<String, dynamic>{
      'wsUrl': '  ',
      'projectId': 'abc',
      'pointCode': '',
    });
    expect(AppConfig.wsUrl, AppConfig.defaultWsUrl);
    expect(AppConfig.projectId, AppConfig.defaultProjectId);
    expect(AppConfig.pointCode, AppConfig.defaultPointCode);

    // 合法值要生效；projectId 写成字符串也要认（现场手改容易多打一对引号）
    AppConfig.applyRuntimeConfig(<String, dynamic>{
      'wsUrl': 'wss://example.test/ws',
      'projectId': '7',
      'pointCode': ' point_9 ',
      'pointName': ' 演播室 ',
    });
    expect(AppConfig.wsUrl, 'wss://example.test/ws');
    expect(AppConfig.projectId, 7);
    expect(AppConfig.pointCode, 'point_9');
    expect(AppConfig.pointName, '演播室');

    // 凭据：用户名去空格，密码保留原样（首尾空格可能是密码的一部分），
    // 且必须同时存在才算「配好了」。
    AppConfig.applyRuntimeConfig(<String, dynamic>{
      'username': ' point_1 ',
      'password': ' p w ',
    });
    expect(AppConfig.username, 'point_1');
    expect(AppConfig.password, ' p w ');
    expect(AppConfig.hasCredentials, isTrue);

    // 只配了账号、没配密码时不算「配好了」。
    //
    // 这里直接改字段而不是再 applyRuntimeConfig：空串在 applyRuntimeConfig
    // 里表示「缺字段，保留原值」，用它是清不掉已有密码的。
    AppConfig.username = 'only_user';
    AppConfig.password = '';
    expect(AppConfig.hasCredentials, isFalse);

    // 复位，避免影响其它用例
    AppConfig.applyRuntimeConfig(<String, dynamic>{
      'wsUrl': AppConfig.defaultWsUrl,
      'projectId': AppConfig.defaultProjectId,
      'pointCode': AppConfig.defaultPointCode,
      'pointName': AppConfig.defaultPointName,
      'username': '',
      'password': '',
    });
    expect(AppConfig.hasCredentials, isFalse);
  });
}
