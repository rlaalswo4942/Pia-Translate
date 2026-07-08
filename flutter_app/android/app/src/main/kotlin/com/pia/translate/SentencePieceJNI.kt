package com.pia.translate

object SentencePieceJNI {
    init {
        System.loadLibrary("sp_jni")
    }

    @JvmStatic external fun encode(modelPath: String, text: String): IntArray
    @JvmStatic external fun decode(modelPath: String, ids: IntArray): String
    @JvmStatic external fun encodePieces(modelPath: String, text: String): Array<String>
    @JvmStatic external fun decodePieces(modelPath: String, pieces: Array<String>): String
}
