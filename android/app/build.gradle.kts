plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "dev.sam.speedtest"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    defaultConfig {
        applicationId = "dev.sam.speedtest"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    buildTypes {
        release { signingConfig = signingConfigs.getByName("debug") }
    }
}
flutter { source = "../.." }

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
