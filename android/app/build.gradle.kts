plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aktenak.dosya_dolabi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aktenak.dosya_dolabi"
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

    // Sürüm imzası CI'da (release.yml) ortam değişkenlerinden gelir; anahtar
    // depoda yok. Değişkenler yoksa (yerel geliştirme) debug anahtarı kullanılır.
    // Yayımlanan APK'lar yalnız CI'dan çıkar: v1.1.1'den itibaren hepsi aynı
    // sürüm anahtarıyla imzalı, böylece birbirinin üstüne kurulur.
    val surumAnahtari = System.getenv("DOSYA_DOLABI_KEYSTORE")
    signingConfigs {
        if (surumAnahtari != null) {
            create("surum") {
                storeFile = file(surumAnahtari)
                storePassword = System.getenv("DOSYA_DOLABI_KEYSTORE_PASSWORD")
                keyAlias = "dosya-dolabi"
                keyPassword = System.getenv("DOSYA_DOLABI_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (surumAnahtari != null) "surum" else "debug"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // MainActivity'deki FileProvider için.
    implementation("androidx.core:core-ktx:1.16.0")
}

flutter {
    source = "../.."
}
