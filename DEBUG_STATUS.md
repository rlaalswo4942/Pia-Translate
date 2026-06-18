# Pia-Translate 앱 디버깅 현황

> 이 파일은 서브 기기에서 작업을 이어받을 때 참고용으로 작성됨.
> Claude에게 "DEBUG_STATUS.md 읽고 이어서 진행해줘"라고 하면 됨.

---

## 현재 상태 (2026-06-19 기준)

**앱이 폰에서 열리지 않음.** 설치는 되지만 실행 시 아무 UI도 표시 안 됨.

- 최신 빌드: **v1.3.2**
- 다운로드 페이지: https://rlaalswo4942.github.io/Pia-Translate/
- GitHub Actions로 APK 빌드 → GitHub Releases 자동 업로드 → GitHub Pages 다운로드 링크

---

## 시도한 것들 (버전별)

| 버전 | 변경 내용 | 결과 |
|---|---|---|
| v1.0.9 | drawable/styles.xml 리소스 생성 | 빌드 성공 |
| v1.1.0~v1.1.2 | CMakeLists.txt NDK 링크 오류 수정 | 빌드 성공 |
| v1.1.3 | workflow permissions 추가 (Release 403 오류) | 빌드+배포 성공 |
| v1.1.5 | applicationId 패키지명 불일치 수정 (com.pia.pia_translate → com.pia.translate) | APK 설치 성공, 실행 안됨 (크래시 다이얼로그) |
| v1.1.6~v1.1.7 | debugPrint import 누락 수정 | 동일 크래시 |
| v1.1.8 | onnxruntime 제거 (크래시 원인 격리) | 동일 크래시 |
| v1.1.9 | google_mlkit_text_recognition 제거 | **변화**: 크래시 다이얼로그 → 블랙스크린 (Flutter 엔진은 뜸) |
| v1.2.0 | main.dart runApp() 즉시 호출 (await 없앰) | 블랙스크린 지속 |
| v1.3.0 | speech_to_text 제거, libsp_jni.so 제거, MainActivity 최소화 | 동일 |
| v1.3.1 | **namespace 불일치 수정** (핵심 버그), main.dart 정적 텍스트만 | 동일 |
| v1.3.2 | 플러그인 완전 제거 (Flutter 엔진만), AndroidManifest 최소화 | **미확인** (유저가 아직 테스트 중) |

---

## 확인된 버그들

### 1. namespace 불일치 (v1.3.1에서 수정)
```
scaffold 생성 시:
  namespace    "com.pia.pia_translate"  ← 수정 안 됨 (버그)
  applicationId "com.pia.translate"    ← 수정됨

Flutter 엔진이 applicationId 기준으로 GeneratedPluginRegistrant 클래스를 찾는데
namespace가 달라서 ClassNotFoundException → 모든 플러그인 등록 실패
```
→ workflow에 `sed -i 's/namespace "com\.pia\.pia_translate"/namespace "com.pia.translate"/'` 추가로 수정

### 2. CMakeLists.txt 불필요한 네이티브 빌드
- translator.dart가 stub 상태인데 SentencePiece C++ 라이브러리를 매 빌드마다 컴파일
- v1.3.0에서 제거

### 3. speech_to_text 플러그인
- 일부 기기에서 configureFlutterEngine() 단계 hang 가능성
- v1.3.0에서 제거

---

## 빌드 구조 설명

```
[번역]/
├── flutter_app/          ← Flutter 앱 소스
│   ├── lib/main.dart     ← 현재 진단용 정적 UI
│   ├── pubspec.yaml      ← 플러그인 목록 (v1.3.2 빌드 시 workflow에서 최소화)
│   └── android/
│       ├── app/CMakeLists.txt   ← 유지하되 workflow에서 빌드에 포함 안 함
│       ├── app/src/main/
│       │   ├── AndroidManifest.xml  ← 최소화됨
│       │   └── kotlin/com/pia/translate/MainActivity.kt  ← 최소화됨
│       └── (build.gradle 등은 CI에서 scaffold로 생성)
└── .github/workflows/release.yml  ← 빌드 파이프라인
```

**CI 빌드 방식**: `flutter create` 로 임시 scaffold 생성 → gradle 파일 복사 → applicationId/namespace sed 패치 → `flutter build apk --release`

---

## v1.3.2 테스트 결과에 따른 다음 단계

### v1.3.2가 열리면 (화면에 "Pia 번역" 텍스트 보임)
→ 플러그인 중 하나가 원인. 하나씩 추가해서 범인 특정.
```
추가 순서:
1. shared_preferences + path_provider (기본 저장소)
2. sqflite (DB)
3. image_picker
4. share_plus
5. dio (네트워크)
```

### v1.3.2도 안 열리면
→ 반드시 필요한 정보:
1. **폰 기종** (예: 삼성 갤럭시 A54)
2. **안드로이드 버전** (설정 → 휴대전화 정보)
3. **앱 탭 시 정확한 증상** ("앱이 중지됐습니다" 다이얼로그? / 블랙스크린? / 아무것도 안 뜸?)

→ ADB 로그 수집 방법 (USB 디버깅 가능한 경우):
```bash
# PC에서 ADB 설치 후 폰 연결
adb logcat -c
adb shell am start -n com.pia.translate/.MainActivity
adb logcat -d > crash_log.txt
# crash_log.txt 내용을 Claude에게 붙여넣기
```

---

## 원래 목표 (완료되면 할 것들)

1. 앱 정상 실행 확인 (현재 단계)
2. DataCollector (SQLite 학습 데이터 수집) 복원
3. ONNX 번역 모델 호환 버전 찾아서 복원
4. google_mlkit_text_recognition OCR 복원
5. speech_to_text 음성 인식 복원
6. GitHub Actions "번역 모델 변환" 워크플로우 수동 실행
