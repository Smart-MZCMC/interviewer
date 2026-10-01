/// 没有原生实现时的占位：只存在内存里，进程一结束就丢。
///
/// 覆盖单元测试与任何没有 MainActivity 实现的平台。行为与改动前一致，
/// 只是采访端在这种平台下仍会退化成「每次打开重新登录」，不会崩。
class TokenStore {
  /// 见 token_store_native.dart 里的同名常量。
  static const String storageKind = 'stub';

  String? _token;

  Future<String?> read() async => _token;

  Future<void> write(String token) async => _token = token;

  Future<void> clear() async => _token = null;
}
