plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.safe_vision_app"
    
    // Đã nâng cấp lên 36 để chạy mượt flutter_tts
    compileSdk = 36 
    
    // Đã nâng lên 27 để hỗ trợ Camera và AI (TFLite)
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
        
        // Mức tối thiểu API 26 để AI hoạt động ổn định
        minSdk = 26 
        
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Dùng debug key cho bản demo tạm thời
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}