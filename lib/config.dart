/// 运行期配置。
///
/// 编译期默认值只是兜底：Web 端会用 `web/config.json` 覆盖它们
/// （见 [applyRuntimeConfig]），所以部署到现场后改服务器地址只需要
/// 编辑 `public/interviewer/config.json`，不必重新 `flutter build web`。
///
/// 全写成编译期常量会带来一个很麻烦的问题：现场不知道服务器地址，
/// 就只能先问清楚、回源码改、重新构建、重新部署整个采访端。
class AppConfig {
  // ---- 编译期默认值 ----
  // 默认指向正式域名，直接编译出来的产物也能连上。
  // 换地址时改 web/config.json 即可，不用动这里。
  static const String defaultWsUrl = 'ws://zhdb.647382.xyz/ws';
  static const int defaultProjectId = 1;
  static const String defaultPointCode = 'point_1';
  static const String defaultPointName = '采访点 1';

  // ---- 实际生效值：可被 config.json 覆盖 ----
  // 不能是 const：main() 里还要在 runApp 之前赋值。
  static String wsUrl = defaultWsUrl;
  static int projectId = defaultProjectId;
  static String pointCode = defaultPointCode;
  static String pointName = defaultPointName;

  // 状态枚举，全平台一致，保持常量。
  static const String statusReady = 'ready';
  static const String statusPreparing = 'preparing';
  static const String statusNotReady = 'not_ready';
  static const String statusOffline = 'offline';

  /// 用 config.json 的内容覆盖默认值。
  ///
  /// 逐字段校验：类型不对或缺失就保留默认值，绝不因为配置文件写错
  /// 就让整个采访端起不来。
  static void applyRuntimeConfig(Map<String, dynamic> json) {
    final ws = json['wsUrl'];
    if (ws is String && ws.trim().isNotEmpty) {
      wsUrl = ws.trim();
    }

    final pid = json['projectId'];
    if (pid is int && pid > 0) {
      projectId = pid;
    } else if (pid is String) {
      // JSON 里写成 "1" 也接受——现场手改配置很容易在数字上多加一对引号。
      final parsed = int.tryParse(pid.trim());
      if (parsed != null && parsed > 0) {
        projectId = parsed;
      }
    }

    final code = json['pointCode'];
    if (code is String && code.trim().isNotEmpty) {
      pointCode = code.trim();
    }

    final name = json['pointName'];
    if (name is String && name.trim().isNotEmpty) {
      pointName = name.trim();
    }
  }
}
