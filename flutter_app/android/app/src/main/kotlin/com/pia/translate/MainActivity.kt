package com.pia.translate

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.pia.translate/sentencepiece"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
}

/** JNI 브릿지 — sp_jni.cpp 와 연결 */
object SentencePieceJNI {
    init {
        System.loadLibrary("sp_jni")
    }

    @JvmStatic
    external fun encode(modelPath: String, text: String): IntArray

    @JvmStatic
    external fun decode(modelPath: String, ids: IntArray): String
}
