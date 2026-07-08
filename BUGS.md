# Pia 번역 — 미해결 오류 목록

## 🔴 현재 미해결

(현재 없음 — 아래 BUG-003/BUG-004 모두 2026-07-09 세션에서 원인 확정 및 수정 적용, 실기기 검증 대기)

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
| (2026-07-08) | BUG-002 수정 후에도 EOS 미도달 반복 (당시 INT8 양자화 부작용으로 추정) | INT8 동적 양자화로 EOS 토큰 확률이 greedy top5 밖으로 밀려남으로 추정 (FP32 원본은 정상 종료됨을 로컬 검증으로 확인) | repetition_penalty 1.3→3.0, no_repeat_ngram 3→2, EOS 점증 부스팅(3스텝 이후 매 스텝 +0.8) 추가. 실기기 확인: 무한반복 사라짐. 커밋 `ad401fd`. **→ 진짜 근본 원인은 BUG-004로 판명, 이 완화값들은 안전망으로 유지** |
| **BUG-004 (2026-07-09)** | **무한 반복의 진짜 근본 원인**: 인코더 입력(`input_ids`)에 EOS 토큰을 안 붙이고 그대로 ONNX에 넣고 있었음. 학습 시 소스 시퀀스는 항상 `</s>`로 끝나는데 이게 없으면 디코더가 EOS를 예측 못 하고 첫 토큰 근처를 무한 반복함 | `translator.dart`의 `_spEncode`가 순수 피스→id 변환만 하고 EOS를 안 붙임 | **FP32 opus-mt-ko-en(양자화 전혀 없음)로 로컬 재현 — EOS 없이는 "Hi Hi Hi Hi..." 무한반복, EOS 붙이면 "Hello." 로 즉시 정상 종료.** BUG-002/BUG-001과 무관하게 애초부터 있던 문제였고, INT8 양자화는 증상을 악화시켰을 뿐 근본 원인이 아니었음. `_onnxInfer`에서 `encInputIds = [...inputIds, eosId]`로 인코더 입력 끝에 EOS 부착하도록 수정 (전 언어쌍 공통 적용) |
| **BUG-003 (2026-07-09)** | en_ko(tc-big 폴백) 모델 자체 품질 낮음 — "hello world"→"cosmos ?? Cosc、코스" 등 의미 불일치 | `opus-mt-en-ko`(401 게이트로 접근 불가) 폴백인 `opus-mt-tc-big-en-ko` 자체가 저품질 모델(BLEU 13.7). 대체 검토한 NLLB-200 계열은 품질은 좋으나 **CC-BY-NC-4.0(비상업 전용)** 라이선스라 상업화 계획과 충돌하여 제외 | **`seongs/ke-t5-base-aihub-koen-translation-integrated-10m-en-to-ko`** (T5 아키텍처, 0.2B, AI Hub 한영 1천만 쌍 코퍼스 파인튜닝, **Apache-2.0 — 상업적 이용 가능**)로 교체. 로컬 검증: "hello world"→"안녕하세요, 월드.", "I love this app"→"나는 이 앱을 좋아해." 등 자연스러운 결과 확인(단 BUG-004 EOS 부착 수정이 함께 있어야 정상 동작 — EOS 없으면 이 모델도 무한반복). Marian과 달리 토크나이저가 source.spm/target.spm 분리가 아닌 단일 `spiece.model` — 패키징 시 동일 파일을 양쪽 이름으로 복사, vocab.json은 `tokenizer.get_vocab()`으로 생성 |
