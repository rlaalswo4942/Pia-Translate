package com.pia.translate

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SP_CHANNEL = "com.pia.translate/sentencepiece"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "encode" -> {
                        val modelPath = call.argument<String>("modelPath") ?: ""
                        val text      = call.argument<String>("text") ?: ""
                        try {
                            result.success(SentencePieceJNI.encode(modelPath, text).toList())
                        } catch (e: Exception) {
                            result.error("ENCODE_ERROR", e.message, null)
                        }
                    }
                    "decode" -> {
                        val modelPath = call.argument<String>("modelPath") ?: ""
                        val ids       = call.argument<List<Int>>("ids")
                                            ?.toIntArray() ?: IntArray(0)
                        try {
                            result.success(SentencePieceJNI.decode(modelPath, ids))
                        } catch (e: Exception) {
                            result.error("DECODE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
