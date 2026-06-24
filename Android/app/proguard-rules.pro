# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Preserve line numbers for readable crash stack traces, but hide source names.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ── DEVOPS-02: keep rules for kotlinx-serialization + Supabase SDK ──────────
# kotlinx.serialization generates synthetic serializer classes and relies on
# @Serializable/@SerialName annotations + Companion.serializer() at runtime.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

# Keep @Serializable model classes and their generated serializers.
-keepclassmembers @kotlinx.serialization.Serializable class ** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keep class **$$serializer { *; }
-keepclasseswithmembers class ** {
    @kotlinx.serialization.SerialName <fields>;
}

# Supabase / Ktor keep rules.
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**

# Project model classes are serialized over PostgREST — keep them intact.
-keep class com.example.tavattendance.data.models.** { *; }