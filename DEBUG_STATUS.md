# Pia-Translate 앱 디버깅 현황

> 이 파일은 서브 기기에서 작업을 이어받을 때 참고용으로 작성됨.
> Claude에게 **"DEBUG_STATUS.md 읽고 이어서 진행해줘"** 라고 하면 됨.

---

## 현재 상태 (2026-07-09 기준 — 세션 일시 중단, 이어서 작업 예정)

**BUG-003(en_ko 저품질)·BUG-004(EOS 미부착 근본원인) 모두 원인 확정 및 수정 완료, 코드/모델 배포까지 끝남.
실기기 최종 확인만 중단된 상태 — 재개 시 "우선순위 0" 부터 이어서 하면 됨.**

### 우선순위 0: 실기기 확인 재개 (중단 지점)

- 새 APK 설치 완료(`com.pia.translate`), 모델 8개 다운로드도 완료된 상태에서 중단함.
- 앱을 영어→한국어로 전환(스왑 버튼 원본좌표 약 (541,321))까지 확인함.
- adb `input tap`으로 입력창 포커스 후 `input text "hello%sworld"`를 보냈는데 **텍스트가 실제로 안 들어감**
  (스크린샷상 입력창이 계속 placeholder 상태, 소프트키보드는 뜨는데 한글 자판이 떠 있어서 영문 입력이 씹혔을 가능성).
  → 재개 시: 키보드를 영문 모드로 전환하거나(`오/한` 키 토글), `adb shell input keyevent` 조합으로 자모 대신
  직접 텍스트 주입, 혹은 `uiautomator dump`로 EditText 포커스 상태를 먼저 확인 후 재시도할 것.
- adb: `C:\Users\com\AppData\Local\Android\Sdk\platform-tools\adb.exe`, 기기 `R3CT701SC3R` (Samsung SM_S906N).
- 테스트 문장: "hello world", "I love this app", "Where is the nearest subway station?" 등
  (로컬 Python 검증 결과와 실기기 결과 일치하는지 확인 목적).

### 이번 세션에서 처리한 것 (커밋 `e40ec4f`, `4e8174a`, 모두 push 완료)

1. **BUG-004(진짜 근본 원인, 신규 발견)**: 인코더 입력에 EOS 토큰을 안 붙이던 문제.
   FP32 opus-mt-ko-en으로 로컬 재현 — EOS 없으면 "Hi Hi Hi...", 붙이면 "Hello."로 정상 종료.
   기존에 BUG-002 이후 "INT8 양자화 부작용"으로 추정했던 반복 루프의 진짜 원인이었음(양자화는 증상만 악화).
   `translator.dart`의 `_onnxInfer`에서 `encInputIds = [...inputIds, eosId]`로 전 언어쌍 공통 수정. 커밋 `e40ec4f`.
2. **BUG-003(en_ko 저품질) 해결**: `Helsinki-NLP/opus-mt-tc-big-en-ko` → `seongs/ke-t5-base-aihub-koen-
   translation-integrated-10m-en-to-ko`(T5, 0.2B, AI Hub 1천만 쌍, **Apache-2.0**)로 교체.
   NLLB는 품질 더 좋았지만 **CC-BY-NC 라이선스라 상업화 계획과 충돌**해 제외(사용자 확인함).
   단일 `spiece.model` 토크나이저라 `scripts/convert_models.py`에 `SINGLE_SPM_MODELS` 패키징 경로 추가.
   커밋 `e40ec4f`.
3. **CI 보안검사 오탐 수정**: `data_collector.dart`/`home_screen.dart`의 로컬 Wi-Fi 기본값(`localhost:3001`,
   `192.168.0.x`)을 `http://` 평문 검사가 걸러 빌드 실패시키던 것 수정 — 로컬/사설 IP 대역 제외(사용자 승인 후 적용).
   커밋 `4e8174a`.
4. `en_ko.zip`을 `models-v1` 릴리스에 재업로드 완료 (60MB → 243MB, T5가 Marian보다 큰 아키텍처라 커짐).
   릴리스 설명 크기 표도 실측치로 갱신함.
5. CI test-build 빌드 성공 확인(run `28967971588`), APK를 폰에 설치하고 모델 8개 다운로드까지 완료 —
   여기서 사용자 요청으로 세션 중단.
6. 로컬 검증(PyTorch FP32 + 양자화된 ONNX INT8 둘 다, 앱과 동일한 파이프라인 시뮬레이션)에서는
   "hello world"→"안녕하세요", "I love this app"→"나는 이 앱을 좋아해." 등 정상 품질 확인함 —
   **다만 이건 PC 시뮬레이션이고, 실기기(JNI)에서 최종 확인은 아직 안 됨.**

### 검증 방법 (재사용 가능)

`flutter_app`과 별개로 로컬 Python(`transformers`+`onnxruntime`+`sentencepiece`)으로 실제 모델 zip을 풀어
vocab.json 매핑·EOS 부착·디코딩 로직을 그대로 재현하면 실기기 설치 없이 빠르게 검증 가능
(이번 세션에서 BUG-004/en_ko 신모델 검증에 사용한 방법).

- 최신 빌드: test-build (CI workflow_dispatch로 수시 갱신)
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
