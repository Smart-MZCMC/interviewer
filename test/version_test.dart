import 'package:interviewer/version.dart';
import 'package:flutter_test/flutter_test.dart';

/// 版本比较是这个功能的核心：横幅要不要出现、出现时提示「该升哪一边」全看它。
/// 错了的后果是给现场一个方向相反的指引（该升后端却让升客户端）。
void main() {
  group('parseVersion', () {
    test('正常三段与两段', () {
      expect(parseVersion('1.2.3'), [1, 2, 3]);
      expect(parseVersion('1.2'), [1, 2, 0]);
      expect(parseVersion('2'), [2, 0, 0]);
    });

    test('容忍 v 前缀与预发布标记', () {
      expect(parseVersion('v1.2.0'), [1, 2, 0]);
      expect(parseVersion('1.2.0-rc1'), [1, 2, 0]);
      expect(parseVersion('1.2.0+build5'), [1, 2, 0]);
    });

    test('无法解析时返回 null', () {
      // 空串最关键：int.tryParse('') 虽是 null，但若把空段当 0 处理，
      // 会把「开发构建没有版本号」误判成「比服务端旧很多」。
      expect(parseVersion(''), isNull);
      expect(parseVersion('   '), isNull);
      expect(parseVersion('dev'), isNull);
      expect(parseVersion('x.y.z'), isNull);
      expect(parseVersion('1.2.3.4'), isNull);
      expect(parseVersion('1..3'), isNull);
    });
  });

  group('compareVersions', () {
    test('按三段数字比较', () {
      expect(compareVersions('1.2.0', '1.1.0'), 1);
      expect(compareVersions('1.1.0', '1.2.0'), -1);
      expect(compareVersions('2.0.0', '1.9.9'), 1);
      expect(compareVersions('1.0.0', '1.0.1'), -1);
      expect(compareVersions('1.2.3', '1.2.3'), 0);
    });

    test('容忍 v 前缀', () {
      expect(compareVersions('v1.2.0', '1.2.0'), 0);
      expect(compareVersions('v1.3.0', 'v1.2.0'), 1);
    });

    test('段数不足按补零处理', () {
      expect(compareVersions('1.2', '1.1.9'), 1);
      expect(compareVersions('1.2.0', '1.2'), 0);
    });

    test('无法解析时返回 null 而不是猜', () {
      expect(compareVersions('', '1.0.0'), isNull);
      expect(compareVersions('1.0.0', ''), isNull);
      expect(compareVersions('dev', '1.0.0'), isNull);
    });
  });

  group('checkVersion', () {
    test('版本相同 -> 无需提示', () {
      final r = checkVersion('1.2.0', '1.2.0', '1.1.0');
      expect(r.status, VersionStatus.match);
      expect(r.shouldWarn, isFalse);
    });

    // 这是本功能的核心语义：达不到最低适配版本 = 真的有功能异常，
    // 与「只是落后」是两回事，提示样式也不同。
    test('低于最低适配版本 -> 必须更新', () {
      final r = checkVersion('1.1.0', '1.3.0', '1.2.0');
      expect(r.status, VersionStatus.unsupported);
      expect(r.isUrgent, isTrue);
      expect(r.shouldWarn, isTrue);
      expect(r.minimum, '1.2.0');
    });

    test('满足最低适配但落后于后端 -> 只是建议', () {
      final r = checkVersion('1.2.0', '1.3.0', '1.2.0');
      expect(r.status, VersionStatus.clientBehind);
      expect(r.isUrgent, isFalse);
      expect(r.shouldWarn, isTrue);
    });

    test('客户端超前 -> 提示更新后端', () {
      final r = checkVersion('1.3.0', '1.2.0', '1.2.0');
      expect(r.status, VersionStatus.clientAhead);
      expect(r.shouldWarn, isTrue);
    });

    // 老后端没有 min_client_version，退化成「只要不等就提醒」，
    // 而不是因为拿不到最低版本就保持沉默——那会让新客户端对着老后端
    // 静默运行，出问题时更难查。
    test('后端未声明最低适配版本 -> 退化为单纯的不一致提示', () {
      expect(checkVersion('1.1.0', '1.2.0', '').status, VersionStatus.clientBehind);
      // 声明值本身不可解析时同样退化，而不是误判成 unsupported
      expect(checkVersion('1.1.0', '1.2.0', 'dev').status, VersionStatus.clientBehind);
    });

    // 开发构建没注入版本号时不能报不一致，否则每次本地开发都弹假告警。
    test('任一侧不可解析 -> unknown，不当成不一致', () {
      expect(checkVersion('dev', '1.2.0', '1.1.0').status, VersionStatus.unknown);
      expect(checkVersion('', '1.2.0', '1.1.0').status, VersionStatus.unknown);
      expect(checkVersion('1.2.0', '', '1.1.0').status, VersionStatus.unknown);
      expect(checkVersion('dev', 'dev', 'dev').status, VersionStatus.unknown);
    });

    test('结果带上两侧版本号，便于直接写进提示文案', () {
      final r = checkVersion('1.1.0', '1.3.0', '1.2.0');
      expect(r.client, '1.1.0');
      expect(r.server, '1.3.0');
      expect(r.minimum, '1.2.0');
    });
  });
}