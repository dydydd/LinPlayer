plugins {
    id("com.android.application")
}

android {
    namespace = "com.linplayer.tvlegacy"
    compileSdk = 36
    buildToolsVersion = "36.0.0"

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.linplayer.tvlegacy"
        minSdk = 19
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        multiDexEnabled = true
    }

    buildTypes {
        release {
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
    // ijkplayer
    implementation("tv.danmaku.ijk.media:ijkplayer-java:0.8.8")
    implementation("tv.danmaku.ijk.media:ijkplayer-armv7a:0.8.8")
    implementation("tv.danmaku.ijk.media:ijkplayer-arm64:0.8.8")

    // libVLC Android SDK (3.x)
    implementation("org.videolan.android:libvlc-all:3.6.5")

    // QR code (Android 4.4 compatible)
    implementation("com.google.zxing:core:3.5.3")
}
