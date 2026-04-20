import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.Properties
import java.util.zip.GZIPInputStream
import org.gradle.api.tasks.compile.JavaCompile

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun isEnabledFlag(value: String?): Boolean =
    value?.trim()?.lowercase()?.let { it == "1" || it == "true" || it == "yes" } ?: false

fun decodeDartDefines(raw: String?): Map<String, String> {
    val source = raw?.trim().orEmpty()
    if (source.isEmpty()) return emptyMap()

    return source
        .split(',')
        .mapNotNull { encoded ->
            val token = encoded.trim()
            if (token.isEmpty()) return@mapNotNull null

            val decoded =
                runCatching {
                    String(Base64.getUrlDecoder().decode(token), StandardCharsets.UTF_8)
                }.recoverCatching {
                    String(Base64.getDecoder().decode(token), StandardCharsets.UTF_8)
                }.getOrNull() ?: return@mapNotNull null

            val splitAt = decoded.indexOf('=')
            if (splitAt <= 0) return@mapNotNull null

            decoded.substring(0, splitAt) to decoded.substring(splitAt + 1)
        }.toMap()
}

fun patchGeneratedPluginRegistrant(projectDir: File) {
    val registrantFile =
        File(projectDir, "src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
    if (!registrantFile.exists()) return

    var source = registrantFile.readText(Charsets.UTF_8)
    if (source.contains("pluginByClassName(")) return

    source =
        source.replace(
            "import io.flutter.embedding.engine.FlutterEngine;\n",
            "import io.flutter.embedding.engine.FlutterEngine;\n" +
                "import io.flutter.embedding.engine.plugins.FlutterPlugin;\n" +
                "import java.lang.reflect.Constructor;\n\n",
        )

    source =
        source.replace(
            "  private static final String TAG = \"GeneratedPluginRegistrant\";\n",
            "  private static final String TAG = \"GeneratedPluginRegistrant\";\n\n" +
                "  private static FlutterPlugin pluginByClassName(String className) throws Exception {\n" +
                "    Class<?> pluginClass = Class.forName(className);\n" +
                "    Constructor<?> constructor = pluginClass.getDeclaredConstructor();\n" +
                "    constructor.setAccessible(true);\n" +
                "    return (FlutterPlugin) constructor.newInstance();\n" +
                "  }\n\n",
        )

    source =
        Regex("""flutterEngine\.getPlugins\(\)\.add\(new ([A-Za-z0-9_$.]+)\(\)\);""")
            .replace(source) { match ->
                """flutterEngine.getPlugins().add(pluginByClassName("${match.groupValues[1]}"));"""
            }

    registrantFile.writeText(source, Charsets.UTF_8)
}

val targetAbis =
    (project.findProperty("target-platform")?.toString() ?: "")
        .split(',')
        .map { it.trim().lowercase() }
        .filter { it.isNotEmpty() }
        .mapNotNull { platform ->
            when (platform) {
                "android-arm" -> "armeabi-v7a"
                "android-arm64" -> "arm64-v8a"
                "android-x86" -> "x86"
                "android-x64", "android-x86_64" -> "x86_64"
                else -> null
            }
        }
        .distinct()

val dartDefines = decodeDartDefines(project.findProperty("dart-defines")?.toString())
val bundleTvProxy =
    isEnabledFlag(project.findProperty("linplayer.bundleTvProxy")?.toString()) ||
        isEnabledFlag(System.getenv("LINPLAYER_BUNDLE_TV_PROXY")) ||
        isEnabledFlag(dartDefines["LINPLAYER_FORCE_TV"])
val isWindowsHost = System.getProperty("os.name").startsWith("Windows", ignoreCase = true)

android {
    namespace = "com.example.lin_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    val isCi = System.getenv("CI")?.trim()?.lowercase() == "true"
    val allowCiDebugSigning =
        System.getenv("LINPLAYER_ALLOW_CI_DEBUG_SIGNING")?.trim()?.lowercase()
            ?.let { it == "1" || it == "true" || it == "yes" } ?: false

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    fun propOrEnv(propName: String, envName: String): String? {
        val env = System.getenv(envName)?.trim()
        if (!env.isNullOrEmpty()) return env
        val prop = keystoreProperties.getProperty(propName)?.trim()
        return prop?.takeIf { it.isNotEmpty() }
    }

    val releaseKeystoreFile = propOrEnv("storeFile", "ANDROID_KEYSTORE_FILE")
    val releaseStorePassword =
        propOrEnv("storePassword", "ANDROID_KEYSTORE_PASSWORD")
    val releaseKeyAlias = propOrEnv("keyAlias", "ANDROID_KEY_ALIAS")
    val releaseKeyPassword = propOrEnv("keyPassword", "ANDROID_KEY_PASSWORD")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.lin_player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseSigningConfig =
        if (
            releaseKeystoreFile != null &&
                releaseStorePassword != null &&
                releaseKeyAlias != null &&
                releaseKeyPassword != null &&
                file(releaseKeystoreFile).exists()
        ) {
            signingConfigs.create("release") {
                storeFile = file(releaseKeystoreFile)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        } else {
            null
        }

    buildTypes {
        release {
            if (isCi && releaseSigningConfig == null && !allowCiDebugSigning) {
                throw GradleException(
                    "Android release signing is not configured. " +
                        "OTA upgrades require a stable signing key; configure ANDROID_KEYSTORE_* secrets/env vars " +
                        "or set LINPLAYER_ALLOW_CI_DEBUG_SIGNING=true to force debug signing (not OTA-safe).",
                )
            }
            signingConfig = releaseSigningConfig ?: signingConfigs.getByName("debug")
        }
    }

    // Flutter's Gradle plugin keeps a default ABI allowlist to avoid shipping unsupported ABIs.
    // When `-Ptarget-platform=...` is set (e.g. `flutter build apk --target-platform android-arm`),
    // override the allowlist so we don't accidentally bundle native libs for other ABIs
    // (which can make the APK crash on devices that pick the wrong ABI at runtime).
    val isSplitPerAbi = project.hasProperty("split-per-abi")
    if (!isSplitPerAbi && targetAbis.isNotEmpty()) {
        buildTypes.configureEach {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(targetAbis)
            }
        }
    }
}

flutter {
    source = "../.."
}

tasks.withType<JavaCompile>().configureEach {
    doFirst {
        patchGeneratedPluginRegistrant(project.projectDir)
    }
}

tasks.configureEach {
    // Windows machines occasionally leave AGP's lint cache jars locked, which
    // breaks release packaging before assembleRelease can finish.
    if (isWindowsHost && name == "lintVitalAnalyzeRelease") {
        enabled = false
    }
}

val repoRootDir = project.rootDir.parentFile
val mihomoAssetsDir = File(repoRootDir, "assets/tv_proxy/mihomo/android")
val metacubexdAssetFile = File(repoRootDir, "assets/tv_proxy/metacubexd/compressed-dist.tgz")
val generatedMihomoJniLibsDir = File(project.buildDir, "generated/mihomoJniLibs")
val generatedTvProxyAssetsDir = File(project.buildDir, "generated/tvProxyAssets")
val bundledMihomoAbis =
    if (targetAbis.isNotEmpty()) {
        targetAbis
    } else {
        listOf(
            "arm64-v8a",
            "armeabi-v7a",
            "x86_64",
            "x86",
        )
    }

if (bundleTvProxy) {
    // TV-only payloads should never leak into phone/tablet Android builds.
    tasks.register("prepareTvProxyAndroidAssets") {
        inputs.file(metacubexdAssetFile)
        outputs.dir(generatedTvProxyAssetsDir)
        doLast {
            generatedTvProxyAssetsDir.deleteRecursively()
            if (!metacubexdAssetFile.exists()) return@doLast

            val dst = File(generatedTvProxyAssetsDir, "tv_proxy/metacubexd/compressed-dist.tgz")
            dst.parentFile.mkdirs()
            metacubexdAssetFile.copyTo(dst, overwrite = true)
        }
    }

    // Bundle mihomo as a native library executable (libmihomo.so) so it can run on ROMs that mount
    // app-private storage as "noexec" (executing binaries from filesDir will fail with Permission denied).
    tasks.register("prepareMihomoJniLibs") {
        inputs.dir(mihomoAssetsDir)
        outputs.dir(generatedMihomoJniLibsDir)
        doLast {
            generatedMihomoJniLibsDir.deleteRecursively()

            for (abi in bundledMihomoAbis) {
                val src = File(mihomoAssetsDir, "$abi/mihomo.gz")
                if (!src.exists()) continue

                val dst = File(generatedMihomoJniLibsDir, "$abi/libmihomo.so")
                dst.parentFile.mkdirs()
                GZIPInputStream(FileInputStream(src)).use { input ->
                    FileOutputStream(dst).use { output ->
                        input.copyTo(output)
                    }
                }
            }
        }
    }

    android.sourceSets.getByName("main").assets.srcDir(generatedTvProxyAssetsDir)
    android.sourceSets.getByName("main").jniLibs.srcDir(generatedMihomoJniLibsDir)
    tasks.named("preBuild").configure {
        dependsOn("prepareTvProxyAndroidAssets")
        dependsOn("prepareMihomoJniLibs")
    }
}
