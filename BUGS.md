# Pia 번역 — 미해결 오류 목록

## 🔴 현재 미해결

### [BUG-003] en_ko(tc-big 폴백) 모델 자체 품질 낮음
- **증상**: "hello world" → "cosmos ?? Cosc、코스" 등 의미 전혀 안 맞는 출력
- **원인**: `Helsinki-NLP/opus-mt-en-ko`가 401 등으로 실패 시 `Helsinki-NLP/opus-mt-tc-big-en-ko`로 폴백되는데,
  이 tc-big 모델은 로컬 PC에서 **양자화 없는 순정 HuggingFace PyTorch 모델로 재현해도** "hello world"→"제니퍼",
  "good morning"→"킹" 같은 터무니없는 결과가 나옴 (BLEU 13.7, flores101-devtest 기준으로 원래 품질이 낮은 모델).
  BUG-001/002와 무관한 **모델 자체의 한계**임을 2026-07-08 로컬 검증(`transformers` MarianMTModel.generate)으로 확인.
- **해결 방향(미착수)**: en_ko 전용 대체 모델 탐색(예: NLLB 계열 en→kor_Hang 서브셋 추출) 또는 tc-big 품질 감수하고 유지.

---

## ✅ 해결 완료 (참고용)

| 버전 | 오류 | 원인 | 해결 |
|------|------|------|------|
| v1.5.4 | 다운로드 중 ANR | UI 콜백이 메인 스레드 과부하 | Timer.periodic(500ms) 스로틀링 |
| v1.5.5 | ONNX 로딩 ANR | OrtSession.fromFile() 메인 스레드 블로킹 | 영구 백그라운드 Isolate + 세션 캐시 |
| v1.5.6 | ZIP 추출 무한 행 | Android SELinux가 Process.run('unzip') 차단 | archive 패키지 (순수 Dart) |
| v1.5.7 | idx=65000 out of range | BOS 토큰 하드코딩값이 모델 vocab 초과 | config.json 동적 파싱 + 폴백 체인 |
| BUG-001 (2026-07-08) | 번역 결과 반복 출력 ("real real real...") | greedy 디코더에 반복 억제 없음 | no-repeat-ngram + repetition penalty 추가 |
| BUG-002 (2026-07-08) | **오번역 — 언어는 맞는데 내용이 틀림** (예: "안녕하세요"→"여호와하나님") | JNI가 raw SentencePiece 내부 id를 vocab.json id인 것처럼 그대로 ONNX 입출력에 사용 (MarianTokenizer는 spm 내부id가 아니라 vocab.json으로 piece↔id 매핑함) | `encodePieces`/`decodePieces` JNI 추가 + Dart에서 vocab.json 매핑 후 인코딩/디코딩. 로컬 ONNX 재현 검증: "안녕하세요"→"Hi/Hello", "오늘 날씨가 좋네요"→"It's a lovely day..." 등 의미 정확해짐 확인. 커밋 `bf819cd` |
| (2026-07-08) | BUG-002 수정 후에도 EOS 미도달 반복 (INT8 양자화 부작용) | INT8 동적 양자화로 EOS 토큰 확률이 greedy top5 밖으로 밀려남 (FP32 원본은 정상 종료됨을 로컬 검증으로 확인) | repetition_penalty 1.3→3.0, no_repeat_ngram 3→2, EOS 점증 부스팅(3스텝 이후 매 스텝 +0.8) 추가. 실기기 확인: 무한반복 사라짐. 근본 해결(재양자화)은 미착수. 커밋 `ad401fd` |
