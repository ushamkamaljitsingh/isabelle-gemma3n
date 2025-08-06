# android/app/proguard-rules.pro

# ==========================================
# ISABELLE ACCESSIBILITY APP PROGUARD RULES
# Optimized for Gemma 3n E2B deployment
# ==========================================

# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# ==========================================
# MEDIAPIPE LLM INFERENCE PROTECTION
# Critical for Gemma 3n functionality
# ==========================================

# Keep all MediaPipe LLM inference classes
-keep class com.google.mediapipe.tasks.genai.llminference.** { *; }
-keep class com.google.mediapipe.tasks.genai.** { *; }
-keep class com.google.mediapipe.framework.** { *; }

# Keep MediaPipe image classes for vision processing
-keep class com.google.mediapipe.framework.image.** { *; }

# Keep TensorFlow Lite classes (used by MediaPipe)
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }

# ==========================================
# NATIVE LIBRARY PROTECTION
# ==========================================

# Keep JNI methods for MediaPipe native libraries
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep native method names for debugging
-keepnames class * {
    native <methods>;
}

# ==========================================
# KOTLIN COROUTINES (for async AI processing)
# ==========================================

-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# ==========================================
# ANDROID SPECIFICS
# ==========================================

# Keep AndroidX classes
-keep class androidx.** { *; }
-dontwarn androidx.**

# Keep Camera2 API classes for blind mode
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# Keep audio processing classes for deaf mode
-keep class androidx.media.** { *; }

# ==========================================
# ACCESSIBILITY SERVICES
# ==========================================

# Keep accessibility service classes
-keep class * extends android.accessibilityservice.AccessibilityService { *; }

# Keep accessibility node info
-keep class android.view.accessibility.** { *; }

# ==========================================
# SERIALIZATION AND REFLECTION
# ==========================================

# Keep Gson classes for JSON processing
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Keep model classes that use reflection
-keep class com.isabelle.accessibility.models.** { *; }

# ==========================================
# OPTIMIZATION SETTINGS
# ==========================================

# Enable aggressive optimizations
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizationpasses 5
-allowaccessmodification
-dontpreverify

# ==========================================
# LARGE MODEL FILE PROTECTION
# ==========================================

# Don't obfuscate model loading paths
-keep class com.isabelle.accessibility.MainActivity {
    public void copyModelFromAssets(...);
    public java.lang.String getOptimalModelPath();
}

# Keep model file constants
-keep class com.isabelle.accessibility.config.AppConstants {
    public static final java.lang.String MODEL_*;
    public static final java.lang.String DEVICE_MODEL_PATH;
    public static final java.lang.String EXTERNAL_MODEL_PATH;
}

# ==========================================
# DEBUGGING (Remove in production)
# ==========================================

# Keep source file names and line numbers for debugging
-keepattributes SourceFile,LineNumberTable

# Keep custom exception classes
-keep public class * extends java.lang.Exception

# ==========================================
# WARNINGS TO IGNORE
# ==========================================

# Ignore warnings about missing classes that are conditionally loaded
-dontwarn java.lang.ClassValue
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**

# Ignore warnings about reflection in MediaPipe
-dontwarn java.lang.reflect.**

# ==========================================
# ASSET PROTECTION
# ==========================================

# Don't rename asset paths
-keep class * {
    public static final java.lang.String ASSET_*;
}

# Keep asset loading methods
-keep class * {
    public ** loadAsset(...);
    public ** getAssets();
}