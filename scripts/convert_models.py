"""
OPUS-MT → CTranslate2 INT8 변환 스크립트
PC에서 한 번만 실행 → 변환된 모델을 앱 서버에 업로드하거나 폰에 전송

실행:
  pip install -r requirements.txt
  python convert_models.py

출력: ../models/ 폴더에 각 언어쌍 디렉토리 생성
  ko_en/   en_ko/   en_ja/   ja_en/
  en_zh/   zh_en/   en_fr/   fr_en/

크기: INT8 양자화 후 언어쌍당 약 40~60MB
총합: ~400MB (8개 방향)

번역 라우팅:
  ko→en : ko_en 직접
  ko→ja : ko_en → en_ja  (영어 피벗)
  ko→zh : ko_en → en_zh  (영어 피벗)
  ko→fr : ko_en → en_fr  (영어 피벗)
  en→ko : en_ko 직접
  ja→ko : ja_en → en_ko  (영어 피벗)
  zh→ko : zh_en → en_ko  (영어 피벗)
  fr→ko : fr_en → en_ko  (영어 피벗)
"""

import subprocess
import sys
import shutil
from pathlib import Path

OUTPUT_DIR = Path(__file__).parent.parent / "models"

MODELS = {
    "ko_en": "Helsinki-NLP/opus-mt-ko-en",
    "en_ko": "Helsinki-NLP/opus-mt-en-ko",
    "en_ja": "Helsinki-NLP/opus-mt-en-jap",
    "ja_en": "Helsinki-NLP/opus-mt-jap-en",
    "en_zh": "Helsinki-NLP/opus-mt-en-zh",
    "zh_en": "Helsinki-NLP/opus-mt-zh-en",
    "en_fr": "Helsinki-NLP/opus-mt-en-ROMANCE",
    "fr_en": "Helsinki-NLP/opus-mt-fr-en",
}

# en_fr 에 ROMANCE 대신 더 정확한 모델이 있으면 교체
# Helsinki-NLP/opus-mt-tc-big-en-fr 도 가능 (더 크지만 품질 우수)


def _check_deps() -> bool:
    try:
        import ctranslate2
        import sentencepiece
        from transformers import MarianTokenizer
        return True
    except ImportError as e:
        print(f"[오류] 패키지 미설치: {e}")
        print("       pip install -r requirements.txt 실행 후 다시 시도하세요.")
        return False


def convert_model(name: str, hf_id: str) -> bool:
    out = OUTPUT_DIR / name
    tok_out = out / "tokenizer"

    if out.exists() and tok_out.exists():
        size_mb = sum(f.stat().st_size for f in out.rglob("*") if f.is_file()) / 1024 / 1024
        print(f"  [skip] {name:8s}  (이미 존재: {size_mb:.0f}MB)")
        return True

    print(f"  [변환] {name:8s}  {hf_id}")
    try:
        # 1. CTranslate2 CLI로 변환 (HF 자동 다운로드 + INT8 양자화)
        ret = subprocess.run(
            [
                sys.executable, "-m", "ctranslate2.bin.ct2-opus-mt-converter",
                "--model", hf_id,
                "--output_dir", str(out),
                "--quantization", "int8",
                "--force",
            ],
            capture_output=True, text=True
        )

        # CLI 이름이 다를 경우 대안 시도
        if ret.returncode != 0:
            ret = subprocess.run(
                ["ct2-opus-mt-converter",
                 "--model", hf_id,
                 "--output_dir", str(out),
                 "--quantization", "int8",
                 "--force"],
                capture_output=True, text=True
            )

        if ret.returncode != 0:
            # Python API 직접 호출 fallback
            import ctranslate2.converters as conv
            converter = conv.OpusMTConverter(hf_id)
            converter.convert(str(out), quantization="int8", force=True)

        # 2. 토크나이저 저장 (source.spm, target.spm 포함)
        from transformers import MarianTokenizer
        tok = MarianTokenizer.from_pretrained(hf_id)
        tok.save_pretrained(str(tok_out))

        size_mb = sum(f.stat().st_size for f in out.rglob("*") if f.is_file()) / 1024 / 1024
        print(f"  [완료] {name:8s}  {size_mb:.0f}MB")
        return True

    except Exception as e:
        print(f"  [실패] {name:8s}  {e}")
        if out.exists():
            shutil.rmtree(out, ignore_errors=True)
        return False


def main():
    if not _check_deps():
        return

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"\nOPUS-MT → CTranslate2 INT8 변환\n출력: {OUTPUT_DIR.resolve()}\n")

    results = {}
    for name, hf_id in MODELS.items():
        results[name] = convert_model(name, hf_id)

    ok = sum(results.values())
    print(f"\n{'─'*45}")
    print(f"결과: {ok}/{len(MODELS)} 성공")
    for name, success in results.items():
        mark = "✓" if success else "✗"
        print(f"  {mark} {name}")

    if ok > 0:
        total_mb = sum(
            f.stat().st_size for f in OUTPUT_DIR.rglob("*") if f.is_file()
        ) / 1024 / 1024
        print(f"\n총 크기: {total_mb:.0f}MB")
        print(f"\n다음 단계:")
        print(f"  1. 모델을 HuggingFace Hub 또는 서버에 업로드")
        print(f"  2. flutter_app/lib/core/config.dart 에 모델 다운로드 URL 설정")
        print(f"  3. 앱 빌드: cd flutter_app && flutter build apk")


if __name__ == "__main__":
    main()
