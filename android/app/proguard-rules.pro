# ProGuard / R8 Rules for BoardMate AI

# Flutter Framework & Plugin Engine
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Prevent obfuscation of generated plugin registrations
-keep public class * extends io.flutter.plugin.common.PluginRegistry.PluginRegistrantCallback { *; }
-keep public class * extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }

# Google Play Services & Firebase
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Firebase RTDB & Auth
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keepclassmembers class com.google.firebase.** {
    public <init>(...);
    public <fields>;
    public <methods>;
}

# Firebase App Check & Play Integrity / Play Core Deferred Components
-keep class com.google.firebase.appcheck.** { *; }
-keep class com.google.android.play.core.integrity.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Domain Models & JSON Serialization (BoardMate AI)
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep class com.boardmate.boardmate.** { *; }

# Preserve Line Numbers for Crash Reporting / Stack Traces
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable
