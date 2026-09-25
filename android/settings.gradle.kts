pluginManagement {
    val flutterSdkPath =
        run {
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
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // Required for Jetpack Compose on Kotlin 2.0+ (the compiler-extension-
    // version approach used before Kotlin 2.0 no longer applies) — backs
    // the native editor screen's UI (NativeEditorActivity). Pinned to the
    // same version as org.jetbrains.kotlin.android above, per Google's
    // own guidance that this plugin tracks the Kotlin version 1:1.
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.0" apply false
}

include(":app")
