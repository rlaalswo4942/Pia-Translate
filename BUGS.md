# Pia 번역 — 미해결 오류 목록

## 🔴 현재 미해결

### [BUG-001] 번역 결과 반복 출력
- **증상**: 번역 결과가 같은 단어/구절이 계속 반복됨 ("real real real real...")
- **재현**: "안녕하세요" ko→en 번역 시 확인됨
- **진단 로그 (v1.5.20 실기기)**:
  ```
  [ONNX] bosId=65000 (출처:decoder_start_token_id) eosId=0 cfgFound=true  ← 정상
  [ONNX] 디코더 완료: 128스텝 → 128토큰 생성
  [ONNX] 출력 토큰ID(앞20): [431, 431, 431, 431, ...]
  [ONNX] 유니크 토큰: 1 / 전체: 128 (반복률: 99%)
  ```
- **확정 원인**: BOS/EOS 정상, config.json 정상 → greedy 디코더에 반복 억제 없음
  - 토큰 431("real")이 매 스텝 최고 logit → EOS(0) 절대 미도달 → maxLen(128)까지 반복
- **수정 내용** (코드 변경 완료, 커밋 대기):
  - `translator.dart` `_onnxInfer()` 에 추가:
    - `noRepeatNgramSize = 3`: 동일 3-그램 재등장 시 해당 토큰 금지
    - `repetitionPenalty = 1.3`: 출현한 토큰 logit ÷ 1.3 (HuggingFace 기본값)
    - 인코더 히든 상태 검증 로그 추가 (min/max/mean/nan)
    - 디코더 종료 원인 로그 추가 (EOS도달 vs maxLen도달)
- **현재 상태**: 수정 완료, 실기기 재테스트 필요 (커밋 안 함)

---

## ✅ 해결 완료 (참고용)

| 버전 | 오류 | 원인 | 해결 |
|------|------|------|------|
| v1.5.4 | 다운로드 중 ANR | UI 콜백이 메인 스레드 과부하 | Timer.periodic(500ms) 스로틀링 |
| v1.5.5 | ONNX 로딩 ANR | OrtSession.fromFile() 메인 스레드 블로킹 | 영구 백그라운드 Isolate + 세션 캐시 |
| v1.5.6 | ZIP 추출 무한 행 | Android SELinux가 Process.run('unzip') 차단 | archive 패키지 (순수 Dart) |
| v1.5.7 | idx=65000 out of range | BOS 토큰 하드코딩값이 모델 vocab 초과 | config.json 동적 파싱 + 폴백 체인 |
