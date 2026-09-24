import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
val bundledDanmaku = Properties().apply {
    System.getenv("KAZUMITV_DANMAKU_FILE")?.let { path -> file(path).inputStream().use { load(it) } }
}
fun quoted(value:String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r") + "\""
android {
    namespace = "org.kazumi.tv"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.znbsf.kazumi.compose.tv"
        minSdk = 24
        targetSdk = 36
        versionCode = 53
        versionName = "0.3.3"
        buildConfigField("String", "DANDAN_APP_ID", quoted(bundledDanmaku.getProperty("DANDANAPI_APPID", "")))
        buildConfigField("String", "DANDAN_APP_SECRET", quoted(bundledDanmaku.getProperty("DANDANAPI_KEY", "")))
        testInstrumentationRunner = "org.kazumi.tv.TvNetworkInstrumentation"
    }
    buildFeatures { compose = true; buildConfig = true }
    buildTypes { getByName("release") { isMinifyEnabled = false; signingConfig = signingConfigs.getByName("debug") } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.05.01"))
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.webkit:webkit:1.12.0")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.tv:tv-material:1.0.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("org.jsoup:jsoup:1.21.1")
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-exoplayer-hls:1.8.0")
    implementation("androidx.media3:media3-exoplayer-dash:1.8.0")
    implementation("androidx.media3:media3-ui:1.8.0")
    implementation("androidx.media3:media3-session:1.8.0")
    implementation("androidx.media3:media3-datasource-okhttp:1.8.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("org.json:json:20250517")
    testImplementation("junit:junit:4.13.2")
}
