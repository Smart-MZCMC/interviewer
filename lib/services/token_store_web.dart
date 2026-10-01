import 'package:web/web.dart' as web;

/// Web 端的 JWT 持久化：localStorage。
///
/// 采访端主要就是浏览器里开着的一个页面，所以这一份实现才是常态路径。
///
/// 放 localStorage 而不是 sessionStorage 是有意的：sessionStorage 会在
/// 关闭标签页时清掉，于是「关掉重开」又退回重新登录。
///
/// 安全性上没有额外收益可谈：这个应用的账号口令本来就在同目录的
/// config.json 里明文下发，XSS 早就能拿到比令牌更值钱的东西。
class TokenStore {
  static const String _key = 'mzcmc.jwt';

  Future<String?> read() async {
    try {
      final value = web.window.localStorage.getItem(_key);
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      // 隐私模式 / 存储被禁用时 localStorage 会抛，登录走内存即可。
      return null;
    }
  }

  Future<void> write(String token) async {
    try {
      web.window.localStorage.setItem(_key, token);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      web.window.localStorage.removeItem(_key);
    } catch (_) {}
  }
}
