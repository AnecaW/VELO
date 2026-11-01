import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.exists()) releasePropertiesFile.inputStream().use { releaseProperties.load(it) }
val veloBuildDefines = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(',')
    .mapNotNull { encoded ->
        runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8).split('=', limit = 2) }
            .getOrNull()?.takeIf { it.size == 2 }
    }
    .associate { it[0] to it[1] }

android {
    namespace = "com.example.bike_computer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.bike_computer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["veloCleartextTraffic"] = if (veloBuildDefines["VELO_LAN_MODE"] == "true") "true" else "false"
    }

    signingConfigs {
        create("personalRelease") {
            if (releasePropertiesFile.exists()) {
                storeFile = rootProject.file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("personalRelease")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
