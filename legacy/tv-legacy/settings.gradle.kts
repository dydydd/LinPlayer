pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // ijkplayer artifacts (Bintray/JCenter is gone; this repository mirrors the required coordinates)
        maven {
            url = uri("https://artifactory.appodeal.com/appodeal-public/")
        }
        maven {
            url = uri("https://artifacts.videolan.org/libvlc-android/")
        }
    }
}

rootProject.name = "linplayer-tv-legacy"
include(":app")
