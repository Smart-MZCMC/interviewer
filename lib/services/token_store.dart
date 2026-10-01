/// JWT 的本地持久化。
///
/// 为什么不用 shared_preferences：那个包会拖进 shared_preferences_android
/// 原生模块，在 Windows 上构建 APK 时会让 Kotlin 增量缓存崩掉
/// （Could not close incremental caches ... .tab）。这里只需要记住一个字符串，
/// 不值得为它换一个会打断构建的依赖，所以 Android 侧走 MainActivity 里
/// 自己写的平台通道。
///
/// Web 侧用 localStorage，单元测试与没有原生实现的平台落到 stub。
library;

export 'token_store_stub.dart'
    if (dart.library.js_interop) 'token_store_web.dart'
    if (dart.library.io) 'token_store_native.dart';
