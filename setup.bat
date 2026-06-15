@echo off
chcp 65001 > nul
title Pia 번역 앱 — 초기 설정

echo =====================================================
echo   Pia 오프라인 번역 앱 설정
echo   PC 없이 폰에서 완전 로컬 실행
echo =====================================================
echo.

:: ── 1. Flutter 확인 ───────────────────────────────────
flutter --version > nul 2>&1
if errorlevel 1 (
    echo [오류] Flutter가 설치되어 있지 않습니다.
    echo        https://flutter.dev/docs/get-started/install 에서 설치하세요.
    pause & exit /b 1
)
echo [OK] Flutter 설치 확인

:: ── 2. Android NDK 확인 ────────────────────────────────
echo.
echo [안내] Android NDK 가 필요합니다.
echo        Android Studio ^> SDK Manager ^> SDK Tools ^> NDK (Side by side) 체크
echo        또는: sdkmanager "ndk;26.1.10909125"
echo.

:: ── 3. Flutter 의존성 설치 ──────────────────────────────
cd flutter_app
echo [설치] Flutter 패키지 설치 중...
flutter pub get
if errorlevel 1 (
    echo [오류] flutter pub get 실패
    pause & exit /b 1
)
echo [OK] Flutter 패키지 설치 완료

:: ── 4. 모델 변환 안내 ────────────────────────────────────
echo.
echo ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo  [다음 단계]
echo.
echo  1. 번역 모델 변환 (PC에서 한 번):
echo     cd ..\scripts
echo     pip install -r requirements.txt
echo     python convert_models.py
echo.
echo  2. 변환된 models\ 폴더를 서버/허브에 업로드
echo     (HuggingFace Hub 권장)
echo.
echo  3. flutter_app\lib\core\config.dart 에서
echo     modelBaseUrl 을 업로드 주소로 변경
echo.
echo  4. APK 빌드:
echo     flutter build apk --release
echo     결과: build\app\outputs\flutter-apk\app-release.apk
echo.
echo  5. 폰에 설치:
echo     flutter install
echo     또는 adb install build\...\app-release.apk
echo ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo.
pause
