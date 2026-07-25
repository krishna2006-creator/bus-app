plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    
    // Add the Google services Gradle plugin
    id("com.google.gms.google-services")
}

android {
    namespace = "com.agni.bus.tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.agni.bus.tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Import the Firebase BoM
    // The Firebase BoM lets you specify the versions of all Firebase libraries
    // and ensures that all library versions are compatible
    implementation(platform("com.google.firebase:firebase-bom:34.6.0"))

    // Import Firebase Authentication
    implementation("com.google.firebase:firebase-auth")

    // Import Firebase Realtime Database
    implementation("com.google.firebase:firebase-database")

    // Import Firebase Analytics
    implementation("com.google.firebase:firebase-analytics")

    // Import Firebase Cloud Messaging (for notifications)
    implementation("com.google.firebase:firebase-messaging")

    // Import Google Sign-In (for Google authentication)
    implementation("com.google.android.gms:play-services-auth:21.0.0")

    // Import Google Play services
    implementation("com.google.android.gms:play-services-base:18.3.0")

    // Core library desugaring for Java 8+ features (required by flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
