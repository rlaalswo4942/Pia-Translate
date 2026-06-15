/**
 * SentencePiece JNI 래퍼
 * sentencepiece C++ 라이브러리를 Kotlin에서 호출하기 위한 브릿지
 *
 * 빌드: CMakeLists.txt 에서 sentencepiece-static 링크
 */

#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>
#include "sentencepiece_processor.h"

#define LOG_TAG "PiaSP"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// SentencePiece 프로세서 캐시 (모델 경로 → 프로세서)
// 간단하게 마지막 로드된 모델 하나만 캐시
static sentencepiece::SentencePieceProcessor g_sp;
static std::string g_loaded_model = "";

static bool loadModel(const std::string& model_path) {
    if (g_loaded_model == model_path) return true;
    const auto status = g_sp.Load(model_path);
    if (!status.ok()) {
        LOGE("SentencePiece 모델 로드 실패: %s", status.ToString().c_str());
        return false;
    }
    g_loaded_model = model_path;
    return true;
}

extern "C" {

/**
 * 텍스트 → 토큰 ID 배열
 * 반환: jintArray (token IDs)
 */
JNIEXPORT jintArray JNICALL
Java_com_pia_translate_SentencePieceJNI_encode(
    JNIEnv* env, jclass /*clazz*/,
    jstring model_path_j, jstring text_j
) {
    const char* model_path = env->GetStringUTFChars(model_path_j, nullptr);
    const char* text       = env->GetStringUTFChars(text_j,       nullptr);

    jintArray result = env->NewIntArray(0);

    if (loadModel(std::string(model_path))) {
        std::vector<int> ids;
        const auto status = g_sp.Encode(text, &ids);
        if (status.ok()) {
            result = env->NewIntArray(static_cast<jsize>(ids.size()));
            env->SetIntArrayRegion(result, 0, static_cast<jsize>(ids.size()),
                                   reinterpret_cast<const jint*>(ids.data()));
        } else {
            LOGE("Encode 실패: %s", status.ToString().c_str());
        }
    }

    env->ReleaseStringUTFChars(model_path_j, model_path);
    env->ReleaseStringUTFChars(text_j,       text);
    return result;
}

/**
 * 토큰 ID 배열 → 텍스트
 * 반환: jstring (decoded text)
 */
JNIEXPORT jstring JNICALL
Java_com_pia_translate_SentencePieceJNI_decode(
    JNIEnv* env, jclass /*clazz*/,
    jstring model_path_j, jintArray ids_j
) {
    const char* model_path = env->GetStringUTFChars(model_path_j, nullptr);

    jstring result = env->NewStringUTF("");

    if (loadModel(std::string(model_path))) {
        const jsize len = env->GetArrayLength(ids_j);
        jint* ids_raw = env->GetIntArrayElements(ids_j, nullptr);

        std::vector<int> ids(ids_raw, ids_raw + len);
        std::string decoded;
        const auto status = g_sp.Decode(ids, &decoded);
        if (status.ok()) {
            result = env->NewStringUTF(decoded.c_str());
        } else {
            LOGE("Decode 실패: %s", status.ToString().c_str());
        }

        env->ReleaseIntArrayElements(ids_j, ids_raw, JNI_ABORT);
    }

    env->ReleaseStringUTFChars(model_path_j, model_path);
    return result;
}

} // extern "C"
