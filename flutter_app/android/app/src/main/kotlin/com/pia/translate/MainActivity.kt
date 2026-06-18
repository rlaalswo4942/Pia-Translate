package com.pia.translate

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val SP_CHANNEL    = "com.pia.translate/sentencepiece"
    private val CRASH_CHANNEL = "com.pia.translate/crash"

    override fun onCreate(savedInstanceState: Bundle?) {
        // Java/JVM 레벨 크래시를 filesDir에 기록 → 다음 실행 때 Dart가 읽어서 화면에 표시
        val crashFile = File(filesDir, "pia_crash.txt")
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val msg = buildString {
                    appendLine("[Java Crash]")
                    appendLine("Thread: ${thread.name}")
                    appendLine("${throwable::class.qualifiedName}: ${throwable.message}")
                    appendLine(throwable.stackTraceToString())
                }
                crashFile.writeText(msg)
                Log.e("PiaCrash", msg)
            } catch (_: Exception) {}
            prev?.uncaughtException(thread, throwable)
        }

        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 크래시 로그 채널 — Dart가 파일 경로 없이 직접 조회
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CRASH_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCrashLog" -> {
                    val crashFile = File(filesDir, "pia_crash.txt")
                    if (crashFile.exists()) {
                        val log = crashFile.readText()
                        crashFile.delete()
                        result.success(log)
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // SentencePiece JNI 채널
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SP_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "encode" -> {
                    val modelPath = call.argument<String>("modelPath") ?: ""
                    val text      = call.argument<String>("text")      ?: ""
                    try {
                        val ids = SentencePieceJNI.encode(modelPath, text)
                        result.success(ids.toList())
                    } catch (e: Exception) {
                        result.error("SP_ENCODE_ERROR", e.message, null)
                    }
                }
                "decode" -> {
                    val modelPath = call.argument<String>("modelPath") ?: ""
                    val ids       = call.argument<List<Int>>("ids")    ?: emptyList()
                    try {
                        val text = SentencePieceJNI.decode(modelPath, ids.toIntArray())
                        result.success(text)
                    } catch (e: Exception) {
                        result.error("SP_DECODE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

/** JNI 브릿지 — sp_jni.cpp 와 연결 */
object SentencePieceJNI {
    private var loaded = false
    init {
        try {
            System.loadLibrary("sp_jni")
            loaded = true
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.e("PiaSP", "sp_jni load failed: $e")
        }
    }

    @JvmStatic
    external fun encode(modelPath: String, text: String): IntArray

    @JvmStatic
    external fun decode(modelPath: String, ids: IntArray): String
}
