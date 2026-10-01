/// 版本比较。
///
/// 本端版本由构建时注入（`--dart-define=APP_VERSION=1.2.0`），服务端版本
/// 来自 `GET /api/status`。两者不同时界面要提示该更新哪一端，所以必须能
/// 比较大小，而不是只比是否相等。
///
/// 与管理后台（admin/src/lib/version.ts）保持同一套语义。
library;

/// 本端版本。开发构建没有注入时是 `dev`。
///
/// 必须在构建时注入而不是运行时读 pubspec.yaml：普通 `flutter build` 不带
/// `--dart-define` 时会得到空串，于是每次本地开发都弹出一条「请更新客户端」
/// 的假告警，而真正需要提醒的现场反而被淹没。
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'dev',
);

/// 解析版本号为三段数字；无法解析时返回 null。
///
/// 先判空再转数字很关键：`int.tryParse('')` 返回 null，但手写解析若直接
/// `int.parse` 会抛异常；而把空串当 0 处理则会得出「比服务端旧很多」的错误结论。
List<int>? parseVersion(String version) {
  var cleaned = version.trim();
  if (cleaned.isEmpty) return null;
  if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
    cleaned = cleaned.substring(1);
  }
  // 去掉预发布/构建元数据：1.2.0-rc1+build → 1.2.0
  for (final sep in ['-', '+']) {
    final i = cleaned.indexOf(sep);
    if (i >= 0) cleaned = cleaned.substring(0, i);
  }

  final parts = cleaned.split('.');
  if (parts.isEmpty || parts.length > 3) return null;

  final out = <int>[0, 0, 0];
  for (var i = 0; i < parts.length; i++) {
    final raw = parts[i].trim();
    if (raw.isEmpty) return null;
    final n = int.tryParse(raw);
    if (n == null) return null;
    out[i] = n;
  }
  return out;
}

/// 比较两个版本：-1 a 更旧，0 相同，1 a 更新。无法解析时返回 null。
int? compareVersions(String a, String b) {
  final pa = parseVersion(a);
  final pb = parseVersion(b);
  if (pa == null || pb == null) return null;
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}

/// 版本关系的判断结果。
enum VersionStatus {
  /// 无法比较（开发构建、后端没返回版本号、或格式非法）。
  unknown,

  /// 一致，且满足最低适配要求。
  match,

  /// 低于后端要求的最低适配版本：老版本会有功能异常，必须更新。
  unsupported,

  /// 满足最低要求、只是落后于后端：建议更新，不影响使用。
  clientBehind,

  /// 本端新于后端：服务端可能缺少接口，该更新后端。
  clientAhead,
}

/// 本次比较的完整结果，供界面显示两侧版本号。
class VersionCheck {
  final VersionStatus status;
  final String client;
  final String server;
  final String minimum;

  const VersionCheck(this.status, this.client, this.server, this.minimum);

  /// 只有这一档才意味着「现在就有功能异常」，界面才该用醒目的样式。
  bool get isUrgent => status == VersionStatus.unsupported;

  /// 是否需要显示横幅。
  bool get shouldWarn =>
      status != VersionStatus.match && status != VersionStatus.unknown;
}

/// 扩展：让状态自己回答「要不要提示」「是不是紧急」。
///
/// 写在枚举上而不是让调用点写 switch，是为了三个端（导播/采访/.NET）
/// 不会各自漏掉某一档——漏掉一档的后果是「低于最低适配版本却提示成
/// 只是建议」。
extension VersionStatusX on VersionStatus {
  /// 是否需要显示横幅。只有 match 与 unknown 不显示。
  bool get shouldWarn => this != VersionStatus.match && this != VersionStatus.unknown;

  /// 是否意味着「现在就有功能异常」，界面该用醒目样式。
  bool get isUrgent => this == VersionStatus.unsupported;
}

/// 比对本端、服务端与「最低适配版本」。
///
/// 为什么不能简单地「两端不等就告警」：后端发新版不代表客户端必须跟着重建。
/// 改个文案、修个 bug 对客户端完全透明，那样每次发版都会把所有客户端提醒一遍，
/// 久而久之这个提示就没人看了——告警只有在该响的时候响才有意义。
///
/// 分两档（见后端 status_controller.go 的 MinClientVersion 说明）：
///   - 低于最低适配版本 → unsupported，必须更新
///   - 满足最低要求但落后 → clientBehind，只是建议
///
/// 老后端没有 min_client_version 字段，此时退化为「只要不等就提醒」，
/// 而不是因为拿不到最低版本就保持沉默。
VersionCheck checkVersion(
  String client,
  String server,
  String minClientVersion,
) {
  if (client.isEmpty || server.isEmpty) {
    return const VersionCheck(VersionStatus.unknown, '', '', '');
  }

  final cmpToServer = compareVersions(client, server);
  if (cmpToServer == null) {
    return const VersionCheck(VersionStatus.unknown, '', '', '');
  }
  if (cmpToServer == 0) {
    return VersionCheck(VersionStatus.match, client, server, minClientVersion);
  }
  if (cmpToServer > 0) {
    return VersionCheck(VersionStatus.clientAhead, client, server, minClientVersion);
  }

  if (minClientVersion.isNotEmpty) {
    final cmpToMin = compareVersions(client, minClientVersion);
    if (cmpToMin != null && cmpToMin < 0) {
      return VersionCheck(VersionStatus.unsupported, client, server, minClientVersion);
    }
  }
  return VersionCheck(VersionStatus.clientBehind, client, server, minClientVersion);
}