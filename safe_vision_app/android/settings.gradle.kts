// Android build entry point.
// Plugin management is configured here before the project is evaluated.

pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // AGP 8.7.3 is the minimum version that supports compileSdk 36
    // and stays compatible with the NDK used by tflite_flutter.
    id("com.android.application") version "8.7.3" apply false

    // Kotlin 2.1.0 is compatible with AGP 8.7.3.
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
