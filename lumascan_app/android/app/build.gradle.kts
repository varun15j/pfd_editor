import java.util.Properties

// The app's name comes from appName in lib/app/app_info.dart, the one place
// it is set, so the launcher label always matches the name inside the app.
val appName: String = Regex("""const appName = '([^']+)';""")
    .find(rootProject.file("../lib/app/app_info.dart").readText())
    ?.groupValues?.get(1)
    ?: error("appName not found in lib/app/app_info.dart")

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing for Google Play. android/key.properties (never committed)
// names the upload keystore; see docs/in-app-purchases.md. Without it,
// release builds are signed with the debug key so `flutter run --release`
// still works, but Play rejects those bundles.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.mobi.scanner"
    // permission_handler_android 13.x requires Android API 37 at compile time.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mobi.scanner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // cunning_document_scanner needs 24; the design docs propose 26.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // OneDrive sign-in returns to the app through this scheme. It must
        // match CloudConfig.microsoftRedirectUri (lib/app/cloud_config.dart).
        manifestPlaceholders["appAuthRedirectScheme"] = "com.mobi.scanner"
        manifestPlaceholders["appName"] = appName
    }

    signingConfigs {
        if (keyProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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

dependencies {
    // Tesseract for the Indian scripts ML Kit cannot read (TesseractOcr.kt).
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
    // ML Kit's Devanagari model (Hindi, Marathi), about 4 MB. The plugin
    // bundles Latin only.
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")
}
