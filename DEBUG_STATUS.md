# Pia-Translate 앱 디버깅 현황

> 이 파일은 서브 기기에서 작업을 이어받을 때 참고용으로 작성됨.
> Claude에게 **"DEBUG_STATUS.md 읽고 이어서 진행해줘"** 라고 하면 됨.

---

## 현재 상태 (2026-06-19 v1.5.7 기준)

**앱 실행 성공, 모델 다운로드+압축 해제 성공, 번역 오류 수정 진행 중**

- 최신 빌드: **v1.5.7** (CI 빌드 후 배포 예정)
- 다운로드 페이지: https://rlaalswo4942.github.io/Pia-Translate/
- 저장소: https://github.com/rlaalswo4942/Pia-Translate

---

## 해결된 문제 목록 (v1.5.x)

| 버전 | 문제 | 원인 | 수정 내용 |
|---|---|---|---|
| v1.5.1 | 번역 결과가 원문 그대로 나옴 | 모델 미다운로드 시 에러 숨김, >>fr<< 접두사 누락 | runTranslation 에러 체크, _modelLangPrefix 추가 |
| v1.5.2 | DNS 조회 실패 (Failed host lookup) | AndroidManifest.xml에 INTERNET 권한 없음 | INTERNET/CAMERA/RECORD_AUDIO 권한 추가 |
| v1.5.3 | 다운로드 중 ANR | onProgress 매 청크마다 notifyListeners() → 초당 수백회 호출 | 250ms 스로틀 추가 |
| v1.5.4 | ANR 지속 | 250ms 스로틀도 충분하지 않음, STT 다운로드엔 스로틀 없음 | Timer.periodic(500ms)으로 UI 업데이트 완전 분리 |
| v1.5.5 | 다운로드 후 ANR | OrtSession.fromFile()이 메인 스레드에서 동기 블로킹 (수 초) | ONNX 세션 로딩+추론 전체를 compute() isolate로 이동 |
| v1.5.6 | 다운로드 완료 후 무한 행 | Process.run('unzip')이 Android SELinux로 차단됨 | archive 패키지(순수 Dart)로 교체, compute isolate에서 실행 |
| v1.5.7 | 번역 오류: idx=65000 out of range | bosId=65000 하드코딩 → ko_en 디코더 어휘(46276)에서 범위 초과 | config.json에서 동적 읽기, 50000 초과 시 0으로 폴백 |

---

## 현재 남은 오류 및 다음 작업

### 우선순위 1: 번역 결과 확인 (v1.5.7 테스트)
v1.5.7 APK를 설치하고 아래를 테스트:
1. 한국어 → 영어: "안녕하세요" → "Hello" 또는 유사 결과 확인
2. 한국어 → 일본어: 동일하게 테스트
3. **빈 결과 나오면**: BOS 토큰이 0인데 모델이 즉시 EOS를 출력하는 것 → 각 모델의 실제 decoder_start_token_id 조사 필요

### 우선순위 2: 번역이 여전히 안 되는 경우 조사 방법

`config.json`이 모델 ZIP에 포함되어 있는지 확인:
```
앱 데이터 폴더: /data/data/com.pia.translate/files/models/ko_en/
파일 목록: encoder_model.onnx, decoder_model.onnx, tokenizer/, config.json(?)
```

config.json이 없으면 → 모델 ZIP 재패키징 필요 (아래 참고)

### 우선순위 3: 모델 재패키징 필요한 경우

로컬 PC에서 다음 스크립트로 config.json이 포함된 ZIP을 새로 만들어 models-v1 릴리즈에 업로드:

```python
# 모델이 이미 변환되어 있다고 가정
# optimum-cli 변환 결과 폴더에 config.json이 있어야 함
import zipfile, os

models = ['ko_en', 'en_ko', 'ko_ja', 'ja_ko', 'ko_zh', 'zh_ko', 'en_fr']
for model in models:
    with zipfile.ZipFile(f'{model}.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(model):
            for file in files:
                filepath = os.path.join(root, file)
                arcname = os.path.relpath(filepath, os.path.dirname(model))
                zf.write(filepath, arcname)
    print(f'{model}.zip 생성 완료')
```

### 우선순위 4: decoder_start_token_id 값 확인

각 모델의 올바른 BOS 토큰 확인 방법 (PC Python):
```python
from transformers import MarianConfig

models = {
    'ko_en': 'Helsinki-NLP/opus-mt-ko-en',
    'en_ko': 'Helsinki-NLP/opus-mt-en-ko',
    'ko_ja': 'Helsinki-NLP/opus-mt-ko-jap',
    'ko_zh': 'Helsinki-NLP/opus-mt-ko-zh',
    'en_fr': 'Helsinki-NLP/opus-mt-en-ROMANCE',
}
for name, model_id in models.items():
    cfg = MarianConfig.from_pretrained(model_id)
    print(f'{name}: decoder_start={cfg.decoder_start_token_id}, eos={cfg.eos_token_id}, vocab={cfg.vocab_size}')
```

---

## 앱 구조 (v1.5.x 기준)

```
flutter_app/lib/
├── main.dart                    ← CI가 실제 앱으로 교체 (로컬은 스텁)
├── screens/home_screen.dart
├── services/
│   ├── translator.dart          ← ONNX 번역 엔진 (v1.5.7: BOS 동적 결정)
│   ├── model_manager.dart       ← 모델 다운로드/압축해제 (v1.5.6: archive 패키지)
│   ├── data_collector.dart
│   ├── ocr_service.dart
│   ├── stt_service.dart
│   ├── tts_service.dart
│   └── text_normalizer.dart
├── state/translate_notifier.dart ← UI 상태 (v1.5.4: Timer 기반 UI 업데이트)
└── widgets/
```

## 빌드 구조 핵심

- CI: `.github/workflows/release.yml`
- 로컬 `pubspec.yaml`과 `main.dart`는 스텁 — CI가 빌드 시 교체
- `flutter push` → tag 또는 workflow_dispatch → APK 자동 빌드
- 모델: `models-v1` 태그 릴리즈에 각 언어쌍 ZIP (~60MB/개)

## 번역 경로

```
ko → en: [ko_en]
ko → ja: [ko_en, en_ja]  (ko_en으로 영어 피벗 → en_ja로 일본어)
ko → zh: [ko_en, en_zh]
ko → fr: [ko_en, en_fr]  (en_fr은 >>fr<< 접두사 필요)
en → ko: [en_ko]
```

---

## 이전 디버깅 기록 (v1.3.2까지)

| 버전 | 변경 내용 | 결과 |
|---|---|---|
| v1.0.9 | drawable/styles.xml 리소스 생성 | 빌드 성공 |
| v1.1.5 | applicationId 패키지명 수정 (com.pia.pia_translate → com.pia.translate) | APK 설치 성공, 실행 안됨 |
| v1.1.9 | google_mlkit_text_recognition 제거 | 블랙스크린으로 변화 |
| v1.3.1 | namespace 불일치 버그 수정 | 빌드 성공 |
| v1.3.3 | Flutter 3.32.2 + Kotlin DSL + R8 dontwarn 수정 | 빌드 성공 |
| v1.4.0 | 전체 UI + 플러그인 복원 (onnxruntime 제외) | 빌드 성공 |
| v1.5.0 | ONNX 번역 복원 (onnxruntime 1.4.1 + SentencePiece JNI) | 빌드 성공, 앱 실행 성공 |
