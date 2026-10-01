// TokenStore 的回归测试，重点是**平台通道的参数形状**。
//
// 背景：1.4.2 发出去之后「登录缓存没生效」，真因是 Dart 侧给 write 传了裸
// String，而 Kotlin 侧用 call.argument<String>("token")——argument() 是从
// Map 里按 key 取的，String 没有 "token" 这个 key，于是取出来恒为 null，
// MainActivity 每次都回 bad_args，令牌一个字都没存进去。
//
// 这个 bug 之所以能发出去：Dart 侧类型对、Kotlin 侧能编译、真机上只多一行
// 被 catch 掉的 PlatformException 日志。用 mock channel 把实际发出的
// MethodCall 截下来断言参数形状，才能在 CI 里挡住它。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interviewer/services/token_store.dart';

const _channel = MethodChannel('smart_mzcmc/token_store');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('Android 上必须选中 native 实现，不能落到只存内存的 stub', () {
    expect(
      TokenStore.storageKind,
      'native',
      reason: '条件导入选中了 ${TokenStore.storageKind}。选到 stub 的话 JWT 只存在'
          '内存里，进程一结束就丢——现象正是「登录缓存没生效」。',
    );
  });

  test('write 必须以 Map 传参，否则 Kotlin 的 argument() 取不到值', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      captured = call;
      return null;
    });

    await TokenStore().write('token-abc');

    expect(captured, isNotNull);
    expect(captured!.method, 'write');
    // 关键断言：Kotlin 端按 "token" 这个 key 取值，所以必须是 Map。
    // 这里传 String 的话，对端拿到的是 null，功能静默失效。
    expect(
      captured!.arguments,
      isA<Map<Object?, Object?>>(),
      reason: 'write 的参数必须是 Map —— Kotlin 侧用的是 '
          'call.argument<String>("token")，传裸 String 取出来恒为 null。',
    );
    expect((captured!.arguments as Map)['token'], 'token-abc');
  });

  test('read 能取回 Kotlin 侧返回的值', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'read') return 'from-shared-prefs';
      return null;
    });

    // 换一个实例，确保读到的是平台通道的值而不是内存兜底。
    expect(await TokenStore().read(), 'from-shared-prefs');
  });

  test('clear 之后平台通道里也没有了', () async {
    final storage = <String, String?>{'jwt': 'token-abc'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'read':
          return storage['jwt'];
        case 'write':
          storage['jwt'] = (call.arguments as Map)['token'] as String?;
          return null;
        case 'clear':
          storage['jwt'] = null;
          return null;
      }
      return null;
    });

    await TokenStore().write('token-abc');
    expect(await TokenStore().read(), 'token-abc');
    await TokenStore().clear();
    expect(await TokenStore().read(), isNull);
  });

  test('平台通道抛错时退回内存而不是让调用链崩掉', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      throw PlatformException(code: 'bad_args', message: 'token 为空');
    });

    final store = TokenStore();
    // 写入失败也不能抛——令牌存不住的后果只是重新登录一次。
    await expectLater(store.write('token-abc'), completes);
  });
}