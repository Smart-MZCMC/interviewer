import 'package:flutter/material.dart';

import '../version.dart';
import '../version_service.dart';

/// 版本不一致横幅。
///
/// 两档样式，语义与导播端一致（见 lib/version.dart 的 checkVersion）：
///   - 低于后端声明的最低适配版本 → 红色，表示现在就有功能异常
///   - 只是落后于后端 → 琥珀色，只是建议
///
/// 放在顶部而不是弹窗：采访机位旁常有人操作，弹窗会打断正在进行的播送。
class VersionBanner extends StatefulWidget {
  /// 服务端地址，用于拉取 `GET /api/status`。
  final String serverUrl;

  /// 轮询间隔。默认 5 分钟——这个提示不需要很及时。
  final Duration pollInterval;

  const VersionBanner({
    super.key,
    required this.serverUrl,
    this.pollInterval = const Duration(minutes: 5),
  });

  @override
  State<VersionBanner> createState() => _VersionBannerState();
}

class _VersionBannerState extends State<VersionBanner> {
  VersionInfo? _info;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    final info = await fetchVersionInfo(widget.serverUrl);
    if (!mounted) return;

    setState(() {
      // 服务端版本变了就重新提示：升完服务端，旧横幅不该继续挂着。
      if (_info != null && _info!.serverVersion != info.serverVersion) {
        _dismissed = false;
      }
      _info = info;
    });
  }

  String _message() {
    final info = _info;
    if (info == null) return '';

    final check =
        checkVersion(appVersion, info.serverVersion, info.minClientVersion);
    switch (check.status) {
      case VersionStatus.unsupported:
        return '采访端版本 ${check.client} 已低于服务端要求的最低适配版本 ${check.minimum}，'
            '部分功能可能异常，请尽快更新。';
      case VersionStatus.clientBehind:
        return '采访端版本 ${check.client} 落后于服务端 ${check.server}，建议更新后再使用。';
      case VersionStatus.clientAhead:
        return '采访端版本 ${check.client} 新于服务端 ${check.server}，'
            '服务端可能缺少接口，请升级服务端。';
      case VersionStatus.match:
      case VersionStatus.unknown:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (_dismissed || info == null || !info.status.shouldWarn) {
      return const SizedBox.shrink();
    }

    final urgent = info.status.isUrgent;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: urgent ? scheme.errorContainer : scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: urgent ? scheme.onErrorContainer : scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _message(),
                style: TextStyle(
                  fontSize: 12,
                  color: urgent ? scheme.onErrorContainer : scheme.onTertiaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '本端 v$appVersion',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: (urgent ? scheme.onErrorContainer : scheme.onTertiaryContainer)
                    .withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: urgent ? scheme.onErrorContainer : scheme.onTertiaryContainer,
              tooltip: '知道了',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _dismissed = true),
            ),
          ],
        ),
      ),
    );
  }
}