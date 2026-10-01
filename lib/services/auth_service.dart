import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

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

  /// 丢弃当前令牌，下次 ensureToken 会重新登录。
  static void clear() {
    _token = null;
  }
}
