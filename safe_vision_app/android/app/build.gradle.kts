plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.safe_vision_app"

    // compileSdk 36 is required for the latest APIs used by the
    // camera and permission_handler plugins.
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.safe_vision_app"

        // minSdk 24 (Android 7.0) is the lower bound for the camera2 API
        // and the TFLite GPU delegate used by inference.
        minSdk    = 24
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // For production releases, replace this signingConfig with a
            // keystore configured through key.properties.
            // Debug signing is used for now to keep development simple.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
