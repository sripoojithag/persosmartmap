plugins {
    id("com.android.application")
    id("com.google.gms.google-services") // ✅ Google Services Plugin for Firebase
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.bookmark1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // ✅ This is correct for resolving native plugin issues

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.bookmark1" // ✅ Match this with Firebase project config
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug") // Use real signing config in production
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase Core + Auth + Firestore are declared in pubspec.yaml (not here)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}