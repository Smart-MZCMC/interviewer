package top.laobinghu.smart.mzcmc.interviewer

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 采访端的 Android 宿主。
 *
 * 手写一个 SharedPreferences 通道，而不是引入 shared_preferences 插件：
 * 那个插件会带入 shared_preferences_android 原生模块，在 Windows 上交叉构建
 * 时会让 Kotlin 增量缓存崩掉（Could not close incremental caches ... .tab），
 * 而这里只需要记住一个 JWT 字符串。
 *
 * 存的是应用私有目录下的明文。采访端的主战场其实是浏览器（localStorage），
 * 有效期也由后端 JWT_TTL 控制（默认 60 分钟），过期后服务端会拒绝。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "smart_mzcmc/token_store"
    private val prefsName = "mzcmc_auth"
    private val tokenKey = "jwt"

    private val prefs by lazy { getSharedPreferences(prefsName, Context.MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> result.success(prefs.getString(tokenKey, null))
                    "write" -> {
                        val token = call.argument<String>("token")
                        if (token.isNullOrEmpty()) {
                            result.error("bad_args", "token 为空", null)
                        } else {
                            prefs.edit().putString(tokenKey, token).apply()
                            result.success(null)
                        }
                    }
                    "clear" -> {
                        prefs.edit().remove(tokenKey).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
