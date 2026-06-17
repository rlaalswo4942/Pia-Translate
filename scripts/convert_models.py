"""
OPUS-MT → ONNX 변환 스크립트  (optimum 기반)
앱의 ONNX Runtime이 직접 실행할 수 있는 형식으로 변환 후 ZIP 패키징

실행:
  pip install -r requirements.txt
  python convert_models.py

출력: ../models_zip/  폴더에 <name>.zip 파일 생성
  ZIP 내부 구조 (앱 요구 형식):
    encoder_model.onnx
    decoder_model.onnx
    tokenizer/
      source.spm
      target.spm

크기: 언어쌍당 약 50~80MB  (총 ~500MB)

배포: GitHub Actions convert-models 워크플로우가 자동으로
      GitHub Release 'models-v1' 에 업로드
"""

import shutil
import zipfile
import sys
from pathlib import Path

OUTPUT_DIR = Path(__file__).parent.parent / "models"      # 임시 변환 디렉토리
ZIP_DIR    = Path(__file__).parent.parent / "models_zip"  # 최종 ZIP 출력

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


def _check_deps() -> bool:
    missing = []
    for pkg in ["optimum", "transformers", "sentencepiece", "torch"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print(f"[오류] 패키지 미설치: {', '.join(missing)}")
        print("       pip install -r requirements.txt 실행 후 재시도")
        return False
    return True


def _copy_spm_files(src_dir: Path, tok_dir: Path) -> bool:
    """source.spm / target.spm 파일을 tokenizer/ 하위로 복사."""
    found = list(src_dir.glob("*.spm"))
    if not found:
        # save_pretrained 후 하위 폴더에 있을 수 있음
        found = list(src_dir.rglob("*.spm"))
    if not found:
        print("    [경고] .spm 파일을 찾지 못했습니다 — 토크나이저 수동 확인 필요")
        return False
    tok_dir.mkdir(parents=True, exist_ok=True)
    for f in found:
        dest = tok_dir / f.name
        if not dest.exists():
            shutil.copy(f, dest)
    return True


def convert_model(name: str, hf_id: str) -> bool:
    zip_path = ZIP_DIR / f"{name}.zip"
    if zip_path.exists():
        size_mb = zip_path.stat().st_size / 1024 / 1024
        print(f"  [skip] {name:<8}  ZIP 이미 존재 ({size_mb:.0f}MB)")
        return True

    out_dir = OUTPUT_DIR / name
    tok_dir = out_dir / "tokenizer"
    print(f"  [변환] {name:<8}  ← {hf_id}")

    try:
        from optimum.onnxruntime import ORTModelForSeq2SeqLM
        from transformers import MarianTokenizer

        # ── 1. ONNX 내보내기 ────────────────────────────────────
        print(f"    모델 다운로드 + ONNX 변환 중... (수 분 소요)")
        model = ORTModelForSeq2SeqLM.from_pretrained(hf_id, export=True)
        out_dir.mkdir(parents=True, exist_ok=True)
        model.save_pretrained(str(out_dir))

        # ── 2. SentencePiece 토크나이저 저장 ────────────────────
        tok = MarianTokenizer.from_pretrained(hf_id)
        tok.save_pretrained(str(tok_dir))
        _copy_spm_files(out_dir, tok_dir)

        # ── 3. ZIP 패키징 ────────────────────────────────────────
        # 앱이 기대하는 구조:
        #   encoder_model.onnx
        #   decoder_model.onnx
        #   tokenizer/source.spm
        #   tokenizer/target.spm
        KEEP_EXTS   = {'.onnx', '.spm'}
        KEEP_NAMES  = {'tokenizer_config.json', 'config.json', 'vocab.json'}

        ZIP_DIR.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
            for f in out_dir.rglob("*"):
                if not f.is_file():
                    continue
                if f.suffix in KEEP_EXTS or f.name in KEEP_NAMES:
                    arcname = f.relative_to(out_dir)
                    zf.write(f, arcname)

        size_mb = zip_path.stat().st_size / 1024 / 1024
        print(f"  [완료] {name:<8}  {size_mb:.0f}MB  →  {zip_path.name}")
        return True

    except Exception as e:
        print(f"  [실패] {name:<8}  {e}")
        if out_dir.exists():
            shutil.rmtree(out_dir, ignore_errors=True)
        if zip_path.exists():
            zip_path.unlink()
        return False


def main():
    if not _check_deps():
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    ZIP_DIR.mkdir(parents=True, exist_ok=True)
    print(f"\nOPUS-MT → ONNX 변환  (optimum)\n{'─'*50}")

    results = {name: convert_model(name, hf_id) for name, hf_id in MODELS.items()}

    ok    = sum(results.values())
    total = len(results)
    print(f"\n{'─'*50}")
    print(f"결과: {ok}/{total} 성공")
    for name, success in results.items():
        print(f"  {'✓' if success else '✗'} {name}")

    if ok > 0:
        total_mb = sum(f.stat().st_size for f in ZIP_DIR.glob("*.zip")) / 1024 / 1024
        print(f"\n총 ZIP 크기: {total_mb:.0f}MB  ({ZIP_DIR.resolve()})")
        print("\n다음 단계:")
        print("  GitHub Actions → 'convert-models' 워크플로우 수동 실행")
        print("  → models-v1 Release에 자동 업로드됨")


if __name__ == "__main__":
    main()
