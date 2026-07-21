import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    // Reads app/google-services.json (gitignored — fetch command in PORTING_NOTES.md).
    alias(libs.plugins.google.services)
}

// Supabase credentials live in Andriod/secrets.properties (gitignored).
// Copy secrets.properties.example and fill in the values, or set the
// same names as environment variables (CI).
val secrets = Properties().apply {
    val file = rootProject.file("secrets.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun secretOrNull(name: String): String? = secrets.getProperty(name) ?: System.getenv(name)

fun secret(name: String): String = secretOrNull(name)
    ?: throw GradleException(
        "Missing $name — copy secrets.properties.example to secrets.properties and fill it in."
    )

val releaseSecretNames = listOf("KEYSTORE_FILE", "KEYSTORE_PASSWORD", "KEY_ALIAS", "KEY_PASSWORD")
val releaseSecrets = releaseSecretNames.associateWith(::secretOrNull)
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (releaseRequested && releaseSecrets.values.any { it == null }) {
    throw GradleException("Release signing requires ${releaseSecretNames.filter { releaseSecrets[it] == null }.joinToString()}.")
}

android {
    namespace = "com.example.tavattendance"
    compileSdk {
        version = release(36)
    }

    defaultConfig {
        applicationId = "com.example.tavattendance"
        minSdk = 26
        targetSdk = 36
        versionCode = 4
        versionName = "1.1.1"

        buildConfigField("String", "SUPABASE_PROJECT_URL", "\"${secret("SUPABASE_PROJECT_URL")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${secret("SUPABASE_ANON_KEY")}\"")
    }

    signingConfigs {
        if (releaseSecrets.values.all { it != null }) {
            create("release") {
                storeFile = rootProject.file(releaseSecrets.getValue("KEYSTORE_FILE")!!)
                storePassword = releaseSecrets.getValue("KEYSTORE_PASSWORD")
                keyAlias = releaseSecrets.getValue("KEY_ALIAS")
                keyPassword = releaseSecrets.getValue("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfigs.findByName("release")?.let { signingConfig = it }
            // DEVOPS-02: shrink + obfuscate release builds. The keep rules in
            // proguard-rules.pro preserve the kotlinx-serialization / Supabase
            // metadata that runtime decoding relies on.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.biometric)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    // Supabase
    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.postgrest)
    implementation(libs.supabase.auth)
    implementation(libs.supabase.storage)
    implementation(libs.ktor.client.okhttp)

    // Kiosk QR sign-in (flag qr_sign_in): CameraX preview + ML Kit barcode scanning.
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.mlkit.barcode.scanning)

    // Parent push notifications (flag push_notifications): FCM token + dismissal pushes.
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    testImplementation(libs.junit)
}
