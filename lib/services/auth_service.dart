import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'token_store.dart';

/// 采访端的登录态。
///
/// 为什么采访端也需要登录：后端启用 REQUIRE_PROJECT_MEMBERSHIP 之后，
/// WebSocket 会校验「这个账号是不是这个项目的成员」。采访端此前是匿名的，
/// 开关一开就会当场断连——所以凭据必须在这之前就位。
///
/// 配置里没填账号时不尝试登录，接口保持与改动前一致：开关默认关闭，
/// 存量部署不会因为缺凭据而起不来。
class AuthService {
  static String? _token;
  static bool _loggingIn = false;
  static final TokenStore _store = TokenStore();

  /// 当前令牌；未登录或登录失败时为空。
  static String? get token => _token;

  /// 拿到一个可用令牌。
  ///
  /// 复数并发调用时只有第一次真的发请求（`_loggingIn` 去重）——重连退避
  /// 与心跳可能同时触发，不去重的话一次断线会打出十几条登录日志。
  static Future<String?> ensureToken() async {
    if (_token != null) return _token;
    if (!AppConfig.hasCredentials) return null;
    if (_loggingIn) return null;
    _loggingIn = true;
    try {
      // 先试上次留下的令牌。它多半还有效（后端 JWT_TTL 默认 60 分钟），
      // 而现场是「页面一直开着」——每次刷新都重新登录一次不但吵，
      // 还会让采访端在重新登录的间隙里变成匿名连接。
      final saved = await _store.read();
      if (saved != null && saved.isNotEmpty) {
        if (await _isUsable(saved)) {
          _token = saved;
          debugPrint('[Auth] 复用本地令牌');
          return saved;
        }
        await _store.clear();
      }

      final resp = await http
          .post(
            Uri.parse('${AppConfig.serverUrl}/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': AppConfig.username,
              'password': AppConfig.password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        debugPrint('[Auth] 登录失败 HTTP ${resp.statusCode}: ${resp.body}');
        return null;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic> && decoded['token'] is String) {
        _token = decoded['token'] as String;
        unawaited(_store.write(_token!));
        debugPrint('[Auth] 已登录: ${AppConfig.username}');
        return _token;
      }
      return null;
    } catch (e) {
      debugPrint('[Auth] 登录异常: $e');
      return null;
    } finally {
      _loggingIn = false;
    }
  }

  /// 拿 /api/auth/profile 验一下令牌还认不认。
  ///
  /// 不在本地解析 JWT 的 exp：解析出来也只是「大概还有多久过期」，
  /// 还得额外对付时钟偏移，而后台改密码后旧令牌在服务端已经作废
  /// （token_version 比对）这件事只有真发一次请求才知道。
  static Future<bool> _isUsable(String token) async {
    try {
      final resp = await http
          .get(
            Uri.parse('${AppConfig.serverUrl}/api/auth/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) return true;
      debugPrint('[Auth] 本地令牌已失效 (HTTP ${resp.statusCode})，重新登录');
      return false;
    } catch (e) {
      // 网络不通不等于令牌无效：留着它，下一轮 ensureToken 会再试一次，
      // 总好过把唯一能用的凭据丢掉。
      debugPrint('[Auth] 校验本地令牌失败，沿用: $e');
      return true;
    }
  }

  /// 丢弃当前令牌，下次 ensureToken 会重新登录。
  ///
  /// 只在**确实**被服务端拒绝时调用。页面切后台再切回来不是拒绝信号：
  /// 那里此前调了一次 clear()，于是每次切走再回来都要重新登录一轮，
  /// 记者感知到的就是「这个页面老要我重新登录」。
  static void clear() {
    _token = null;
    unawaited(_store.clear());
  }
}
