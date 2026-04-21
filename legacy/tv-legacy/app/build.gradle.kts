import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
}

fun propOrEnv(properties: Properties, propName: String, envName: String): String? {
    val env = System.getenv(envName)?.trim()
    if (!env.isNullOrEmpty()) return env

    val prop = properties.getProperty(propName)?.trim()
    return prop?.takeIf { it.isNotEmpty() }
}

android {
    namespace = "com.linplayer.tvlegacy"
    compileSdk = 36
    buildToolsVersion = "36.0.0"

    val isCi = System.getenv("CI")?.trim()?.lowercase() == "true"
    val allowCiDebugSigning =
        System.getenv("LINPLAYER_ALLOW_CI_DEBUG_SIGNING")?.trim()?.lowercase()
            ?.let { it == "1" || it == "true" || it == "yes" } ?: false

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    val resolvedVersionCode =
        (
            project.findProperty("linplayer.versionCode")?.toString()
                ?: System.getenv("LINPLAYER_VERSION_CODE")
                ?: System.getenv("BUILD_NUMBER")
            )?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.toIntOrNull()
            ?: 1

    val resolvedVersionName =
        (
            project.findProperty("linplayer.versionName")?.toString()
                ?: System.getenv("LINPLAYER_VERSION_NAME")
                ?: System.getenv("BUILD_NAME")
            )?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: "0.1.0"

    val releaseKeystorePath = propOrEnv(keystoreProperties, "storeFile", "ANDROID_KEYSTORE_FILE")
    val releaseKeystoreFile =
        releaseKeystorePath?.let { configuredPath ->
            // key.properties lives at the legacy project root, so relative storeFile values
            // should be resolved from rootProject rather than the :app module directory.
            if (File(configuredPath).isAbsolute) {
                file(configuredPath)
            } else {
                rootProject.file(configuredPath)
            }
        }
    val releaseStorePassword =
        propOrEnv(keystoreProperties, "storePassword", "ANDROID_KEYSTORE_PASSWORD")
    val releaseKeyAlias = propOrEnv(keystoreProperties, "keyAlias", "ANDROID_KEY_ALIAS")
    val releaseKeyPassword =
        propOrEnv(keystoreProperties, "keyPassword", "ANDROID_KEY_PASSWORD")

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.linplayer.tvlegacy"
        minSdk = 19
        targetSdk = 36
        versionCode = resolvedVersionCode
        versionName = resolvedVersionName

        multiDexEnabled = true
    }

    val releaseSigningConfig =
        if (
            releaseKeystoreFile != null &&
                releaseStorePassword != null &&
                releaseKeyAlias != null &&
                releaseKeyPassword != null &&
                releaseKeystoreFile.exists()
        ) {
            signingConfigs.create("release") {
                storeFile = releaseKeystoreFile
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
                    "Legacy TV release signing is not configured. " +
                        "CI release APKs must use a stable signing key to remain upgradeable.",
                )
            }
            signingConfig = releaseSigningConfig ?: signingConfigs.getByName("debug")
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            pickFirsts += setOf(
                "lib/**/libc++_shared.so",
            )
        }
    }
}

dependencies {
    // UI (Java + XML/View)
    // Keep API 19 compatibility (AndroidX 1.7+ requires API 21+)
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.multidex:multidex:2.0.1")

    // Networking (API 19 compatible)
    implementation("com.squareup.okhttp3:okhttp:3.12.13")

    // Playback cores
    // libVLC Android SDK (3.x)
    implementation("org.videolan.android:libvlc-all:3.6.5")

    // QR code (Android 4.4 compatible)
    implementation("com.google.zxing:core:3.5.3")
}
