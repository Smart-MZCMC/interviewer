// 采访端界面冒烟测试。
//
// 关键点：必须注入假的 WebSocketService。真实连接会发网络请求，
// 失败后还会挂重连 Timer，widget test 结束时会被
// "A Timer is still pending even after the widget tree was disposed" 断言拦下。
// 注入假对象之后，这个测试不依赖任何真实服务器——换服务器地址不会让它变红。

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
