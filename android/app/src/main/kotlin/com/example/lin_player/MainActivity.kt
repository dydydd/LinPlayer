package com.example.lin_player

import android.app.UiModeManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.TrafficStats
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.SocketAddress
import java.net.URI
import kotlin.system.exitProcess

class MainActivity : FlutterActivity() {
    private val channelName = "linplayer/app_icon"
    private val deviceChannelName = "linplayer/device"

    private data class Alias(
        val id: String,
        val classNameSuffix: String,
        val manifestEnabled: Boolean,
    )

    private val aliases = listOf(
        Alias(id = "default", classNameSuffix = ".MainActivityDefault", manifestEnabled = true),
        Alias(id = "pink", classNameSuffix = ".MainActivityPink", manifestEnabled = false),
        Alias(id = "purple", classNameSuffix = ".MainActivityPurple", manifestEnabled = false),
        Alias(id = "miku", classNameSuffix = ".MainActivityMiku", manifestEnabled = false),
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getIcon" -> {
                    result.success(getCurrentIconId())
                }
                "setIcon" -> {
                    val id = call.argument<String>("id") ?: "default"
                    try {
                        setIconId(id)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("set_icon_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAndroidTv" -> result.success(isAndroidTv())
                "batteryLevel" -> result.success(batteryLevel())
                "totalRxBytes" -> result.success(totalRxBytes())
                "primaryAbi" -> result.success(primaryAbi())
                "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                "copyBundledAsset" -> {
                    val assetPath = call.argument<String>("assetPath") ?: ""
                    val destinationPath = call.argument<String>("destinationPath") ?: ""
                    if (assetPath.isBlank() || destinationPath.isBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(copyBundledAsset(assetPath, destinationPath))
                    } catch (e: Exception) {
                        result.error("copy_bundled_asset_failed", e.message, null)
                    }
                }
                "setExecutable" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val f = File(path)
                        // Best-effort. Some ROMs/filesystems may still block execve.
                        f.setReadable(true, true)
                        f.setWritable(true, true)
                        val ok = f.setExecutable(true, true)
                        result.success(ok)
                    } catch (e: Exception) {
                        result.error("set_executable_failed", e.message, null)
                    }
                }
                "setHttpProxy" -> {
                    val host = call.argument<String>("host")
                    val port = call.argument<Int>("port")
                    try {
                        result.success(setHttpProxy(host, port))
                    } catch (e: Exception) {
                        result.error("set_http_proxy_failed", e.message, null)
                    }
                }
                "exitApp" -> {
                    // Exit the app and ensure the process is killed shortly after,
                    // to avoid any background playback or resource leaks.
                    result.success(true)
                    Handler(Looper.getMainLooper()).post {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                finishAndRemoveTask()
                            } else {
                                finish()
                            }
                        } catch (_: Exception) {
                            try {
                                finish()
                            } catch (_: Exception) {
                                // Ignore.
                            }
                        }
                        Handler(Looper.getMainLooper()).postDelayed({
                            Process.killProcess(Process.myPid())
                            exitProcess(0)
                        }, 250)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private class LinPlayerProxySelector(
        private val upstreamHost: String,
        private val upstreamPort: Int,
        private val fallback: ProxySelector?,
    ) : ProxySelector() {
        private val upstream =
            Proxy(Proxy.Type.HTTP, InetSocketAddress(upstreamHost, upstreamPort))

        override fun select(uri: URI?): MutableList<Proxy> {
            if (uri == null) return mutableListOf(Proxy.NO_PROXY)
            val scheme = (uri.scheme ?: "").lowercase()
            if (scheme != "http" && scheme != "https") return mutableListOf(Proxy.NO_PROXY)

            val host = (uri.host ?: "").trim()
            if (host.isEmpty()) return mutableListOf(Proxy.NO_PROXY)
            if (host == "localhost" || host == "127.0.0.1") return mutableListOf(Proxy.NO_PROXY)

            val ip = parseIpv4Literal(host)
            if (ip != null && isPrivateIpv4(ip)) return mutableListOf(Proxy.NO_PROXY)

            return mutableListOf(upstream)
        }

        override fun connectFailed(uri: URI?, sa: SocketAddress?, ioe: IOException?) {
            try {
                fallback?.connectFailed(uri, sa, ioe)
            } catch (_: Exception) {
                // ignore
            }
        }

        private fun parseIpv4Literal(host: String): IntArray? {
            val parts = host.split('.')
            if (parts.size != 4) return null
            val out = IntArray(4)
            for (i in 0..3) {
                val n = parts[i].toIntOrNull() ?: return null
                if (n < 0 || n > 255) return null
                out[i] = n
            }
            return out
        }

        private fun isPrivateIpv4(ip: IntArray): Boolean {
            val a = ip[0]
            val b = ip[1]
            if (a == 10) return true
            if (a == 127) return true
            if (a == 169 && b == 254) return true
            if (a == 192 && b == 168) return true
            if (a == 172 && b in 16..31) return true
            return false
        }
    }

    companion object {
        private var originalProxySelector: ProxySelector? = null
    }

    private fun setHttpProxy(host: String?, port: Int?): Boolean {
        val h = (host ?: "").trim()
        val p = port ?: -1
        if (h.isEmpty() || p <= 0 || p > 65535) {
            val original = originalProxySelector
            if (original != null) {
                ProxySelector.setDefault(original)
            }
            return true
        }

        if (originalProxySelector == null) {
            originalProxySelector = ProxySelector.getDefault()
        }
        ProxySelector.setDefault(
            LinPlayerProxySelector(
                upstreamHost = h,
                upstreamPort = p,
                fallback = originalProxySelector,
            ),
        )
        return true
    }

    private fun isAndroidTv(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true

        val pm = applicationContext.packageManager
        return pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
            pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    private fun batteryLevel(): Int? {
        val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager ?: return null
        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        if (level < 0) return null
        return level
    }

    private fun totalRxBytes(): Long? {
        val v = TrafficStats.getTotalRxBytes()
        if (v == TrafficStats.UNSUPPORTED.toLong()) return null
        if (v < 0) return null
        return v
    }

    private fun copyBundledAsset(assetPath: String, destinationPath: String): Boolean {
        val asset = assetPath.trim().removePrefix("/")
        val destination = destinationPath.trim()
        if (asset.isEmpty() || destination.isEmpty()) return false

        val outFile = File(destination)
        outFile.parentFile?.mkdirs()

        return try {
            applicationContext.assets.open(asset).use { input ->
                outFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            true
        } catch (_: IOException) {
            try {
                outFile.delete()
            } catch (_: Exception) {
                // Ignore cleanup failures.
            }
            false
        }
    }

    private fun primaryAbi(): String? {
        // Best-effort: try to infer the *app* ABI (not the device preference).
        // `Build.SUPPORTED_ABIS[0]` can be arm64 on devices where this app is installed as 32-bit.
        val nativeDir = (applicationInfo.nativeLibraryDir ?: "").trim().lowercase()
        if (nativeDir.isNotEmpty()) {
            // Typical nativeLibraryDir ends with ".../lib/arm" / ".../lib/arm64" / ".../lib/x86" / ".../lib/x86_64".
            val re = Regex("""/(arm64|arm|x86_64|x86)(/|$)""")
            val match = re.find(nativeDir)
            val seg = match?.groupValues?.getOrNull(1) ?: ""
            when (seg) {
                "arm64" -> return "arm64-v8a"
                "arm" -> return "armeabi-v7a"
                "x86_64" -> return "x86_64"
                "x86" -> return "x86"
            }
        }

        val abis = Build.SUPPORTED_ABIS
        if (abis.isEmpty()) return null
        val v = abis[0].trim()
        if (v.isEmpty()) return null
        return v
    }

    private fun setIconId(id: String) {
        val target = aliases.firstOrNull { it.id == id } ?: throw IllegalArgumentException("Unknown icon id: $id")
        val pm = applicationContext.packageManager
        val pkg = applicationContext.packageName

        for (a in aliases) {
            val component = ComponentName(pkg, pkg + a.classNameSuffix)
            val state = if (a.id == target.id) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
        }
    }

    private fun getCurrentIconId(): String {
        val pm = applicationContext.packageManager
        val pkg = applicationContext.packageName
        for (a in aliases) {
            val component = ComponentName(pkg, pkg + a.classNameSuffix)
            val state = pm.getComponentEnabledSetting(component)
            val enabled = when (state) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> a.manifestEnabled
                else -> a.manifestEnabled
            }
            if (enabled) return a.id
        }
        return "default"
    }
}
