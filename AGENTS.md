# Pia-Translate — 작업 가이드라인

> Claude/Codex(GPT)/Gemini 등 어떤 AI 코딩 도구가 붙어도 동일한 맥락으로 이어서 작업하도록 만든 단일 기준 문서입니다.
> Codex 계열은 `AGENTS.md`, Gemini CLI는 `GEMINI.md`를 기본으로 읽습니다 — 새 파일을 따로 만들지 말고 이 문서 하나만 갱신하세요.
> **작업 시작 시 항상 이 순서로 읽을 것: 1) 이 AGENTS.md → 2) `DEBUG_STATUS.md`(중단 지점) → 3) `BUGS.md`(과거 버그 상세) → 4) `git log`**

## 프로젝트 개요
Pia 오프라인 번역 앱 — Flutter + ONNX Runtime, 폰에서 완전 로컬 실행(서버/인터넷 불필요).
- GitHub: `https://github.com/rlaalswo4942/Pia-Translate` — **⚠️ Public 저장소**. 커밋 전 항상 시크릿(API 키, 키스토어, `.env`) 포함 여부 확인. `.gitignore`가 `*.keystore`, `*.jks`, `android/key.properties`, `.env`를 이미 제외 중이니 이 규칙을 절대 깨지 말 것.
- 로컬: `C:\Users\com\Desktop\클로드 전용\[번역]\`
- 다운로드 배포: https://rlaalswo4942.github.io/Pia-Translate/
- **상업화 가능성 있음(사용자 확인, 2026-07-09)** — 번역 모델은 항상 상업적 이용 가능한 라이선스(Apache-2.0/MIT 등)만 사용. NLLB(CC-BY-NC) 등 비상업 전용 라이선스는 품질이 좋아도 채택 금지. 새 모델 후보를 검토할 땐 라이선스부터 확인.

## 핵심 파일
| 파일 | 역할 |
|---|---|
| `flutter_app/lib/services/translator.dart` | ONNX 추론 (compute isolate, BOS/EOS 동적 결정) — 가장 많은 버그가 여기서 발생했음 |
| `flutter_app/lib/services/model_manager.dart` | 모델 다운로드 + archive 추출 |
| `flutter_app/lib/state/translate_notifier.dart` | UI 상태 (Timer 기반) |
| `scripts/convert_models.py` | HF 모델 → ONNX 변환, `SINGLE_SPM_MODELS`(단일 spm 토크나이저 패키징) 처리 |
| `.github/workflows/release.yml` | CI — pubspec/main.dart 교체 포함, APK 빌드 + `models-v1` 릴리스 |
| `DEBUG_STATUS.md` | **현재 세션 중단 지점** — 새로 이어받는 AI는 이 파일부터 확인 |
| `BUGS.md` | 과거 버그(BUG-001~004) 원인·해결 상세 기록 — 같은 실수 반복 방지용, 반드시 먼저 읽고 시작 |

## 번역 경로 (직접 지원 안 되는 언어쌍은 영어 경유)
```
ko→en: [ko_en]           en→ko: [en_ko]
ko→ja: [ko_en, en_ja]    ko→zh: [ko_en, en_zh]
ko→fr: [ko_en, en_fr]    (en_fr은 >>fr<< 접두사 필요)
```

## 이 프로젝트에서 반복 확인된 디버깅 원칙 (BUGS.md 요약, 재발 방지용)
1. **토크나이저 id 체계 혼동 주의** — SentencePiece 내부 id와 vocab.json id는 다름. JNI/네이티브 레이어에서 raw piece id를 그대로 ONNX에 넣으면 언어는 맞는데 의미가 틀린 오번역이 발생함(BUG-002). 항상 vocab.json 매핑을 거칠 것.
2. **EOS 토큰 부착은 인코더 입력에도 필수** — 디코더 EOS뿐 아니라 인코더 `input_ids` 끝에도 EOS가 없으면 무한 반복("Hi Hi Hi...")이 발생함(BUG-004, 진짜 근본원인이었고 이전엔 양자화 부작용으로 오판했었음).
3. **INT8 양자화는 반복 루프의 증상을 악화시킬 뿐 근본 원인이 아님** — 원인 진단 시 항상 FP32 원본으로 먼저 로컬 재현해서 양자화 문제인지 모델/코드 문제인지 분리할 것.
4. **모델 교체 시 토크나이저 구조 확인 필수** — Marian 계열은 source.spm/target.spm 분리, T5 계열은 단일 `spiece.model` — `convert_models.py`의 `SINGLE_SPM_MODELS`처럼 모델 아키텍처별 패키징 분기가 필요함.
5. **실기기 텍스트 입력 시 소프트키보드 언어 상태 주의** — adb `input text`로 영문을 보내도 키보드가 한글 자판이면 씹힐 수 있음. 재현 안 되면 `uiautomator dump`로 포커스/키보드 상태부터 확인.

## 현재 상태 (요약 — 상세는 DEBUG_STATUS.md)
BUG-003(en_ko 저품질)·BUG-004(EOS 미부착) 모두 원인 확정·수정·모델 배포·CI 빌드까지 완료. **실기기 최종 확인 직전에 세션이 중단된 상태**이며, 재개 지점(adb 입력이 실제로 안 들어간 지점)은 `DEBUG_STATUS.md`의 "우선순위 0"에 있음.

## 백업 컨벤션
사용자가 "백업해"라고 지시하면:
1. 이 프로젝트만이 아니라 그 시점에 수정 중인 **워크스페이스의 모든 프로젝트를 각각 개별 커밋**(`backup: YYYY-MM-DD HH:MM`)으로 push까지 완료.
2. 이 저장소는 `claude-workspace` 루트 저장소에 git submodule(`[번역]`)로 등록되어 있음 — push 후 루트에서도 서브모듈 포인터 갱신 커밋 필요.
3. push 후 `pia_dataset`(PostgreSQL, `.env`의 `PIA_DATASET_URL`)의 `dev_logs`에 변경 요약을 project_name="Pia-Translate"로 기록. 새 버그 발견/해결 시 `BUGS.md`도 함께 갱신(DB와 이중 기록).
4. 실기기 디버깅 세션이 중단되는 경우, 반드시 `DEBUG_STATUS.md`를 최신 중단 지점으로 갱신하고 커밋할 것 — 이 파일이 없으면 다음 세션(AI가 바뀌어도)이 처음부터 재현해야 함.

## 보안 체크리스트 (Public 저장소이므로 특히 중요)
- 커밋 전 `git status`/`git diff --staged`로 `.env`, 키스토어, API 키 하드코딩 여부 항상 확인.
- 중앙 DB 연동용 API 키(`data_collector.dart`의 `centralApiKey`)는 앱 내 `SharedPreferences`에만 저장되고 코드에 하드코딩되지 않음 — 이 패턴 유지.
- 모델 라이선스는 Apache-2.0/MIT 등 상업적 이용 가능한 것만 — 새 모델 추가 PR/커밋 시 라이선스 명시.
