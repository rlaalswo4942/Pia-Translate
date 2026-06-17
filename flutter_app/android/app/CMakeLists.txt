cmake_minimum_required(VERSION 3.22.1)
project(pia_translate VERSION 1.0.0 LANGUAGES CXX)

# sentencepiece 를 FetchContent 로 다운로드 & 빌드
include(FetchContent)

FetchContent_Declare(
    sentencepiece
    GIT_REPOSITORY https://github.com/google/sentencepiece.git
    GIT_TAG        v0.2.0
    GIT_SHALLOW    TRUE
)

# 공유 라이브러리 빌드 비활성화 (정적 링크만 사용)
set(SPM_ENABLE_SHARED        OFF CACHE BOOL "" FORCE)
set(SPM_BUILD_TEST           OFF CACHE BOOL "" FORCE)
set(SPM_BUILD_APPS           OFF CACHE BOOL "" FORCE)
set(SPM_USE_EXTERNAL_ABSL    OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(sentencepiece)

# JNI 래퍼 공유 라이브러리
add_library(sp_jni SHARED src/main/cpp/sp_jni.cpp)

target_include_directories(sp_jni PRIVATE
    ${sentencepiece_SOURCE_DIR}/src
)

target_link_libraries(sp_jni
    sentencepiece-static
    android
    log
)

# C++17 사용
set_target_properties(sp_jni PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES
)
