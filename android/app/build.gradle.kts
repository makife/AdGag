import java.util.Properties

plugins {
    id("com.android.application")
    // Deliberately NOT applying org.jetbrains.kotlin.android here: this
    // module already compiles Kotlin (MainActivity.kt) successfully via
    // AGP 9's own built-in Kotlin support, without a separate Kotlin
    // Gradle Plugin — exactly what every build's own warning describes
    // ("plugins that apply KGP" lists only camera_android_camerax/
    // easy_video_editor/ffmpeg_kit_flutter_new_video, never this app
    // module). Applying the legacy KGP plugin alongside AGP's built-in
    // Kotlin is the exact dual-Kotlin-plugin conflict that warning is
    // about — so only the Compose compiler plugin (which needs a Kotlin
    // Gradle Plugin context to hook into) is added below; if this alone
    // isn't sufficient for Compose to compile, that's the first thing
    // to revisit, not adding org.jetbrains.kotlin.android reflexively.
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing with the Play UPLOAD key, read from android/key.properties
// (gitignored, as is the .jks — never commit either). Without that file
// (another machine, CI without the secrets) release builds fall back to the
// debug key: installable for testing, but Play rejects them. Read up here:
// inside android { } "java" means the java extension, not the package.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val uploadStoreFile: String? = keyProperties.getProperty("storeFile")
val uploadStorePassword: String? = keyProperties.getProperty("storePassword")
val uploadKeyAlias: String? = keyProperties.getProperty("keyAlias")
val uploadKeyPassword: String? = keyProperties.getProperty("keyPassword")
val hasUploadKey = uploadStoreFile != null

android {
    namespace = "com.adgag.adgag"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    defaultConfig {
        // The app's identity on Google Play — permanent once the first
        // release is uploaded. (The Kotlin package / `namespace` above stays
        // com.adgag.adgag: it's internal and doesn't have to match.)
        applicationId = "com.ergan.adgag"
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

    signingConfigs {
        if (uploadStoreFile != null) {
            create("release") {
                storeFile = rootProject.file(uploadStoreFile)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasUploadKey) "release" else "debug")
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

// Native editor screen (NativeEditorActivity) dependencies. Versions
// verified live (WebSearch against Maven/Android Developers) before
// pinning, per this project's own standing package-verification
// discipline — not guessed from memory:
// - compose-bom 2026.09.00: latest stable BOM as of this pin.
// - media3 1.11.0: latest stable Media3 release as of this pin.
// CompositionPlayer (media3-transformer) is the specific API this
// screen is built around — it plays a video track and a background
// audio track through ONE Player instance / ONE native clock, which is
// what actually fixes the two-independent-VideoPlayerController drift
// problem the Flutter editor could never fully solve. As of 1.11.0 this
// API is still annotated @UnstableApi by Media3 itself (newer than most
// of ExoPlayer's core, actively evolving) — a real, honest risk to flag,
// not a battle-tested legacy API, but it is Google's own official,
// actively-maintained path for exactly this use case.
dependencies {
    // Pinned to 2026.06.01 (compose-ui 1.11.4), not the newer 2026.09.00 —
    // compose-ui 1.12.x (BOM 2026.08.00+) requires compileSdk 37, which
    // isn't installed in this dev environment's Android SDK (only up to
    // 36) and isn't AGP 9.1.0's recommended max either (36). Confirmed
    // via a real failed build, not guessed: the exact
    // "requires ... compile against version 37" error named
    // ui-text-android:1.12.1 specifically.
    val composeBom = platform("androidx.compose:compose-bom:2026.06.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.13.0")

    implementation("androidx.media3:media3-exoplayer:1.11.0")
    implementation("androidx.media3:media3-transformer:1.11.0")
    implementation("androidx.media3:media3-ui-compose:1.11.0")
    implementation("androidx.media3:media3-common:1.11.0")
    // ScaleAndRotateTransformation (rotate tool) — confirmed via its own
    // real source (implements MatrixTransformation -> GlMatrixTransformation
    // -> GlEffect -> Effect, so it's usable directly in Effects.videoEffects)
    // before adding, per this project's own standing verify-before-use
    // discipline for every Media3 API.
    implementation("androidx.media3:media3-effect:1.11.0")
}
