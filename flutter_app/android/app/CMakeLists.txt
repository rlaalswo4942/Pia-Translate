cmake_minimum_required(VERSION 3.22.1)
project(pia_translate VERSION 1.0.0 LANGUAGES CXX)

include(FetchContent)

FetchContent_Declare(
    sentencepiece
    GIT_REPOSITORY https://github.com/google/sentencepiece.git
    GIT_TAG        v0.2.0
    GIT_SHALLOW    TRUE
)

set(SPM_ENABLE_SHARED        OFF CACHE BOOL "" FORCE)
set(SPM_BUILD_TEST           OFF CACHE BOOL "" FORCE)
set(SPM_BUILD_APPS           OFF CACHE BOOL "" FORCE)
set(SPM_USE_EXTERNAL_ABSL    OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(sentencepiece)

# spm_* command-line tools should be disabled by SPM_BUILD_APPS=OFF.
# If they somehow still exist in the build graph, they need -llog on Android
# (protobuf-lite in sentencepiece references __android_log_write).
if(ANDROID)
    foreach(_spm_target spm_encode spm_decode spm_export_vocab spm_normalize spm_train)
        if(TARGET ${_spm_target})
            # plain (non-keyword) signature to match sentencepiece's own usage style
            target_link_libraries(${_spm_target} log)
        endif()
    endforeach()
endif()

add_library(sp_jni SHARED src/main/cpp/sp_jni.cpp)

target_include_directories(sp_jni PRIVATE
    ${sentencepiece_SOURCE_DIR}/src
)

target_link_libraries(sp_jni
    sentencepiece-static
    android
    log
)

set_target_properties(sp_jni PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES
)

# Android 16+ 16KB 페이지 정렬 필수
if(ANDROID)
    target_link_options(sp_jni PRIVATE "-Wl,-z,max-page-size=16384")
endif()
