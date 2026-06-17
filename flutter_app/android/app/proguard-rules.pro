# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ONNX Runtime
-keep class ai.onnxruntime.** { *; }

# Vosk STT
-keep class org.vosk.** { *; }

# ML Kit OCR
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }

# SentencePiece JNI
-keep class com.example.pia_translate.** { *; }

# SQLite (sqflite)
-keep class com.tekartik.sqflite.** { *; }

# 디버그 로그 제거 — 릴리스 빌드에서 Log.d/v/i 제거
-assumenosideeffects class android.util.Log {
    public static int d(...);
    public static int v(...);
    public static int i(...);
}

# 난독화 시 스택 트레이스 보존 (크래시 분석용)
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
