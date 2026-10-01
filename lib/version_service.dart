/// 版本一致性检查。
///
/// 与管理后台（admin/src/lib/version.ts）、采访端保持同一套语义。
///
/// 数据来源：编译期注入的本端版本（`--dart-define=APP_VERSION`）与服务端
/// `GET /api/status` 返回的 `version` / `min_client_version`。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'version.dart';

/// 一轮版本检查的结果。
class VersionInfo {
  final VersionStatus status;
  final String serverVersion;
  final String minClientVersion;

  const VersionInfo(this.status, this.serverVersion, this.minClientVersion);
}

/// 服务端可达但版本未知时的状态。
const VersionInfo versionUnknown = VersionInfo(VersionStatus.unknown, '', '');

/// 拉一次服务端状态并做版本比对。
///
/// `baseUrl` 传后端地址（不带 /ws 之类后缀），会拼成 `<baseUrl>/api/status`。
/// 该路由是公开的，不需要令牌——这样即使客户端还登不上后台也能拿到版本信息。
///
/// 拿不到就返回 [versionUnknown] 而不是抛异常：内网抖动、服务器重启中都很正常，
/// 不该因此影响采访/导播本身的功能。
Future<VersionInfo> fetchVersionInfo(String baseUrl) async {
  try {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/status');
    final resp = await http.get(uri).timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) return versionUnknown;

    final body = jsonDecode(resp.body);
    if (body is! Map) return versionUnknown;

    final server = (body['version'] as String?)?.trim() ?? '';
    if (server.isEmpty) return versionUnknown;

    final min = (body['min_client_version'] as String?)?.trim() ?? '';
    return VersionInfo(checkVersion(appVersion, server, min).status, server, min);
  } catch (_) {
    return versionUnknown;
  }
}