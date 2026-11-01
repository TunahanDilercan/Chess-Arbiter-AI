import java.util.Properties
import java.io.FileInputStream

// Release signing: create android/key.properties (never commit it):
//   storePassword=...  keyPassword=...  keyAlias=upload  storeFile=/path/upload.jks
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hanova.chessarbiter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Permanent store identity: never change after the first Play upload.
        applicationId = "com.hanova.chessarbiter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // purchases_ui_flutter (Paywalls, Customer Center) needs API 24.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreProperties.containsKey("storeFile")) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Play uploads must use the upload key; without key.properties the
            // build falls back to debug keys so local `--release` runs still work.
            signingConfig = signingConfigs.findByName("release")
                ?: if (System.getenv("REQUIRE_RELEASE_SIGNING") == "true") {
                    // CI store builds must never ship a debug-signed bundle.
                    throw GradleException("key.properties missing: cannot sign the Play upload")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

flutter {
    source = "../.."
}
