import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.clstr.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Eigen, unieke Application ID - com.example.* wordt door Google Play geweigerd.
        applicationId = "com.clstr.app"
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
    }

    // Alleen een release-signingConfig aanmaken als key.properties er echt is.
    // Zonder deze controle ging ELKE gradle-build (ook `flutter run` in debug)
    // hier onderuit op een NullPointerException zodra key.properties ontbrak —
    // bijvoorbeeld op een verse kloon of op een build-server, want dat bestand
    // hoort niet in git.
    val heeftKeystore = keystorePropertiesFile.exists() &&
        keystoreProperties["keyAlias"] != null &&
        keystoreProperties["storeFile"] != null

    signingConfigs {
        if (heeftKeystore) {
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
            // Geen keystore beschikbaar: terugvallen op de debug-sleutel, zodat
            // de build slaagt. Zo'n APK is niet geschikt voor Google Play —
            // daarvoor moet key.properties aanwezig zijn.
            signingConfig = if (heeftKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("WAARSCHUWING: android/key.properties ontbreekt - release wordt met de debug-sleutel ondertekend en is NIET geschikt voor Google Play.")
                signingConfigs.getByName("debug")
            }
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