import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import java.io.File

val useCnMirrors =
    (System.getenv("LINPLAYER_USE_CN_MIRRORS") ?: "")
        .trim()
        .lowercase()
        .let { it == "1" || it == "true" || it == "yes" }

allprojects {
    buildscript {
        repositories {
            if (useCnMirrors) {
                // Helpful for networks that can't reach dl.google.com reliably.
                maven(url = uri("https://maven.aliyun.com/repository/gradle-plugin"))
                maven(url = uri("https://maven.aliyun.com/repository/google"))
                maven(url = uri("https://maven.aliyun.com/repository/central"))
            }
            google()
            mavenCentral()
            gradlePluginPortal()
        }
    }
    repositories {
        if (useCnMirrors) {
            maven(url = uri("https://maven.aliyun.com/repository/google"))
            maven(url = uri("https://maven.aliyun.com/repository/central"))
        }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

fun androidNativePluginPaths(repoRoot: File): Map<String, String> {
    val metadataFile = File(repoRoot, ".flutter-plugins-dependencies")
    if (!metadataFile.exists()) return emptyMap()

    val parsed = JsonSlurper().parseText(metadataFile.readText()) as? Map<*, *> ?: return emptyMap()
    val plugins = parsed["plugins"] as? Map<*, *> ?: return emptyMap()
    val androidPlugins = plugins["android"] as? List<*> ?: return emptyMap()

    return androidPlugins
        .mapNotNull { plugin ->
            val pluginMap = plugin as? Map<*, *> ?: return@mapNotNull null
            val name = pluginMap["name"] as? String ?: return@mapNotNull null
            val path = pluginMap["path"] as? String ?: return@mapNotNull null
            name to path
        }.toMap()
}

fun readPluginFingerprint(file: File): Map<String, String> {
    if (!file.exists()) return emptyMap()
    val parsed = JsonSlurper().parseText(file.readText()) as? Map<*, *> ?: return emptyMap()
    return parsed.entries
        .mapNotNull { (key, value) ->
            val name = key as? String ?: return@mapNotNull null
            val path = value as? String ?: return@mapNotNull null
            name to path
        }.toMap()
}

val repoRootDir = rootProject.projectDir.parentFile
val flutterPluginFingerprintFile = File(newBuildDir.asFile, ".flutter-android-plugin-paths.json")
val currentAndroidPluginPaths = androidNativePluginPaths(repoRootDir)
val previousAndroidPluginPaths = readPluginFingerprint(flutterPluginFingerprintFile)
val changedAndroidPlugins =
    (currentAndroidPluginPaths.keys + previousAndroidPluginPaths.keys)
        .filter { pluginName -> currentAndroidPluginPaths[pluginName] != previousAndroidPluginPaths[pluginName] }

if (changedAndroidPlugins.isNotEmpty()) {
    // Flutter caches Android plugin builds under the shared root build directory.
    // When a dependency upgrade changes a plugin's source path (for example a new
    // pub cache version), purge that plugin's stale build output before Gradle
    // reuses an incompatible classes.jar from the previous version.
    changedAndroidPlugins.forEach { pluginName ->
        delete(newBuildDir.dir(pluginName).asFile)
    }
}

flutterPluginFingerprintFile.parentFile.mkdirs()
flutterPluginFingerprintFile.writeText(JsonOutput.prettyPrint(JsonOutput.toJson(currentAndroidPluginPaths)))

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
