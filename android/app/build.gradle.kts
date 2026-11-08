import java.util.Properties
import java.security.MessageDigest
import groovy.json.JsonSlurper
import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val selectedAbis = (project.findProperty("target-platform") as? String)
    ?.split(",")?.mapNotNull { target ->
        when (target.trim()) {
            "android-arm" -> "armeabi-v7a"
            "android-arm64" -> "arm64-v8a"
            "android-x64" -> "x86_64"
            else -> null
        }
    }.orEmpty().ifEmpty { listOf("arm64-v8a", "x86_64") }
val splitAbis = project.findProperty("split-per-abi")?.toString() == "true"
val rebuiltFfmpeg = rootProject.file("../tools/android/ffmpeg-0.18.1-webp16kb.aar")
val rebuiltJni = rootProject.file("../build/rebuilt_ffmpeg_jni/${selectedAbis.sorted().joinToString("_")}")
// CI credentials remain in the process environment; preserve local signing identity.
val signingEnvironment = mapOf(
    "storeFile" to "ANDROID_KEYSTORE_PATH",
    "storePassword" to "ANDROID_STORE_PASSWORD",
    "keyAlias" to "ANDROID_KEY_ALIAS",
    "keyPassword" to "ANDROID_KEY_PASSWORD",
)
val usingSigningEnvironment = signingEnvironment.values.any { System.getenv(it) != null }
val releaseKeys = Properties().apply {
    if (usingSigningEnvironment) {
        signingEnvironment.forEach { (property, variable) ->
            System.getenv(variable)?.let { setProperty(property, it) }
        }
    } else {
        val keyFile = rootProject.file("key.properties")
        if (keyFile.exists()) keyFile.inputStream().use { load(it) }
    }
}
val validReleaseSigning = signingEnvironment.keys.all {
    !releaseKeys.getProperty(it).isNullOrBlank()
} && rootProject.file(releaseKeys.getProperty("storeFile")).isFile

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release", ignoreCase = true) }) {
        check(validReleaseSigning) {
            "Release signing is required. Configure all four Android signing secrets in CI, or a valid local android/key.properties."
        }
    }
}
if (rebuiltFfmpeg.exists()) {
    val lockFile = rootProject.file("../tools/android/ffmpeg-webp16kb.lock.json")
    check(lockFile.exists()) { "Missing FFmpeg provenance lock. Run scripts/rebuild_android_webp.ps1." }
    val lock = JsonSlurper().parse(lockFile) as Map<*, *>
    val digest = MessageDigest.getInstance("SHA-256")
    rebuiltFfmpeg.inputStream().use { stream ->
        val buffer = ByteArray(65536)
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
    check(actualHash.equals(lock["outputSha256"]?.toString(), ignoreCase = true)) {
        "FFmpeg local AAR hash mismatch. Run scripts/rebuild_android_webp.ps1."
    }
    // Local AAR transforms omit JNI in this AGP/Flutter configuration. Extract
    // only the fixed native filenames from the hash-verified AAR for sourceSets.
    ZipFile(rebuiltFfmpeg).use { archive ->
        for (abi in selectedAbis) {
            for (name in listOf("libffmpeg.so", "libffprobe.so", "libffmpeg.zip.so")) {
                val entry = checkNotNull(archive.getEntry("jni/$abi/$name"))
                val destination = rebuiltJni.resolve("$abi/$name")
                destination.parentFile.mkdirs()
                archive.getInputStream(entry).use { input -> destination.outputStream().use { input.copyTo(it) } }
            }
        }
    }
} else {
    logger.warn("Original FFmpeg dependency has WebP libraries incompatible with 16 KB pages. Run scripts/rebuild_android_webp.ps1 before distribution.")
}

android {
    namespace = "com.aurora.aurora_music"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aurora.aurora_music"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            if (!splitAbis) abiFilters += selectedAbis
        }
    }

    buildTypes {
        configureEach {
            // Override Flutter's broader defaults as well as the defaultConfig.
            ndk.abiFilters.clear()
            if (!splitAbis) ndk.abiFilters += selectedAbis
        }
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (validReleaseSigning) {
                signingConfig = signingConfigs.create("privateRelease") {
                    storeFile = rootProject.file(releaseKeys.getProperty("storeFile"))
                    storePassword = releaseKeys.getProperty("storePassword")
                    keyAlias = releaseKeys.getProperty("keyAlias")
                    keyPassword = releaseKeys.getProperty("keyPassword")
                }
            }
        }
    }
    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += "**/*.zip.so"
        }
    }
    sourceSets.getByName("main").assets.srcDir(rootProject.file("../tools/android/licenses"))
    sourceSets.getByName("main").res.srcDir(rootProject.file("../tools/android/yt-dlp-res"))
    if (rebuiltFfmpeg.exists()) sourceSets.getByName("main").jniLibs.srcDir(rebuiltJni)
}

val prepareAndroidYtDlp by tasks.registering(Exec::class) {
    val script = rootProject.file("../scripts/setup_android_ytdlp.ps1")
    inputs.file(rootProject.file("../scripts/android_ytdlp.lock.json"))
    inputs.file(script)
    outputs.file(rootProject.file("../tools/android/yt-dlp-res/raw/ytdlp"))
    outputs.dir(rootProject.file("../tools/android/licenses"))
    commandLine("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script.absolutePath)
}

tasks.named("preBuild").configure {
    dependsOn(prepareAndroidYtDlp)
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-session:1.11.1")
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    if (rebuiltFfmpeg.exists()) {
        implementation(files(rebuiltFfmpeg))
    } else {
        implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
    }
}


flutter {
    source = "../.."
}
