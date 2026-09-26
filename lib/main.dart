import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  // 必须在 runApp 之前完成：HomeScreen 构造时就会读 AppConfig.pointName，
  // WebSocketService 也会立刻用 wsUrl 建连。
  WidgetsFlutterBinding.ensureInitialized();
  await loadRuntimeConfig();
  runApp(const MyApp());
}

/// 尝试读取同目录下的 `config.json` 覆盖配置。
///
/// 只有 Web 端会这么做——它由后端托管，现场改 `public/interviewer/config.json`
/// 就能换服务器地址，不必重新 `flutter build web`。
/// Android 端没有可写的同目录配置文件，继续用编译期默认值。
///
/// 任何失败都静默忽略并保留默认值：采访端是现场保障用的，
/// 配置文件缺失或写坏都不该让它起不来。
Future<void> loadRuntimeConfig() async {
  if (!kIsWeb) return;
  try {
    // 相对路径。采访端挂在 /interviewer/ 下，这里会解析成
    // /interviewer/config.json，由后端 3002 端口的静态处理器命中。
    final resp = await http.get(Uri.parse('config.json'));
    if (resp.statusCode != 200) return;
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) {
      AppConfig.applyRuntimeConfig(decoded);
      debugPrint('[Config] 已加载 config.json: '
          'ws=${AppConfig.wsUrl} project=${AppConfig.projectId} '
          'point=${AppConfig.pointCode}/${AppConfig.pointName}');
    }
  } catch (e) {
    debugPrint('[Config] 未加载 config.json，沿用编译期默认值: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '采访端',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const HomeScreen(),
    );
  }
}
