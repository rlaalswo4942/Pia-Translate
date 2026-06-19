"""
OPUS-MT → ONNX INT8 변환 스크립트 (optimum 기반)

흐름:
  1. HuggingFace에서 MarianMT 다운로드
  2. FP32 ONNX 내보내기
  3. 동적 INT8 양자화 (encoder + decoder)
  4. ZIP 패키징

출력: models_zip/<name>.zip
  ZIP 내부 구조:
    encoder_model.onnx   ← INT8 양자화
    decoder_model.onnx   ← INT8 양자화
    tokenizer/source.spm
    tokenizer/target.spm

크기 목표: 언어쌍당 50~120MB (FP32 대비 약 1/6 수준)
"""

import gc
import shutil
import zipfile
import sys
from pathlib import Path

OUTPUT_DIR = Path(__file__).parent.parent / "models"
ZIP_DIR    = Path(__file__).parent.parent / "models_zip"

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
    found = list(src_dir.glob("*.spm"))
    if not found:
        found = list(src_dir.rglob("*.spm"))
    if not found:
        print("    [경고] .spm 파일 없음")
        return False
    tok_dir.mkdir(parents=True, exist_ok=True)
    for f in found:
        dest = tok_dir / f.name
        if not dest.exists():
            shutil.copy(f, dest)
    return True


def _quantize_onnx(fp32_dir: Path, q_dir: Path) -> bool:
    """encoder/decoder ONNX를 동적 INT8로 양자화."""
    try:
        from optimum.onnxruntime import ORTQuantizer
        from optimum.onnxruntime.configuration import AutoQuantizationConfig

        # ARM 모바일 최적화 INT8 동적 양자화
        # per_channel=False: 모바일 ORT 호환성 우선
        try:
            qconfig = AutoQuantizationConfig.arm64(
                is_static=False, per_channel=False
            )
        except Exception:
            # optimum 버전에 따라 arm64 없을 수 있음 → avx2 fallback
            qconfig = AutoQuantizationConfig.avx2(
                is_static=False, per_channel=False
            )

        q_dir.mkdir(parents=True, exist_ok=True)

        for model_file in ["encoder_model.onnx", "decoder_model.onnx"]:
            fp32_path = fp32_dir / model_file
            if not fp32_path.exists():
                print(f"    [경고] {model_file} 없음 — 건너뜀")
                continue

            print(f"    INT8 양자화: {model_file} ...")
            quantizer = ORTQuantizer.from_pretrained(
                str(fp32_dir), file_name=model_file
            )
            quantizer.quantize(
                save_dir=str(q_dir),
                quantization_config=qconfig,
            )

            # optimum이 _quantized 접미사로 저장함 → 원래 이름으로 덮어쓰기
            q_name = model_file.replace(".onnx", "_quantized.onnx")
            q_path = q_dir / q_name
            if q_path.exists():
                q_path.rename(q_dir / model_file)

            fp32_mb = fp32_path.stat().st_size / 1024 / 1024
            q_mb    = (q_dir / model_file).stat().st_size / 1024 / 1024
            print(f"      {fp32_mb:.0f}MB → {q_mb:.0f}MB  ({q_mb/fp32_mb*100:.0f}%)")

        return True

    except Exception as e:
        print(f"    [양자화 실패] {e}")
        return False


def convert_model(name: str, hf_id: str) -> bool:
    zip_path = ZIP_DIR / f"{name}.zip"
    if zip_path.exists():
        size_mb = zip_path.stat().st_size / 1024 / 1024
        print(f"  [skip] {name:<8}  ZIP 이미 존재 ({size_mb:.0f}MB)")
        return True

    fp32_dir = OUTPUT_DIR / f"{name}_fp32"
    q_dir    = OUTPUT_DIR / name
    tok_dir  = q_dir / "tokenizer"
    print(f"\n  [{name}]  ← {hf_id}")

    try:
        from optimum.onnxruntime import ORTModelForSeq2SeqLM
        from transformers import MarianTokenizer

        # ── 1. FP32 ONNX 내보내기 ───────────────────────────────
        print(f"    FP32 ONNX 변환 중...")
        model = ORTModelForSeq2SeqLM.from_pretrained(hf_id, export=True)
        fp32_dir.mkdir(parents=True, exist_ok=True)
        model.save_pretrained(str(fp32_dir))
        del model
        gc.collect()

        # ── 2. INT8 동적 양자화 ──────────────────────────────────
        print(f"    INT8 양자화 중...")
        if not _quantize_onnx(fp32_dir, q_dir):
            # 양자화 실패 시 FP32 그대로 사용
            print(f"    [경고] 양자화 실패 — FP32 모델로 대체")
            for f in ["encoder_model.onnx", "decoder_model.onnx"]:
                src = fp32_dir / f
                if src.exists():
                    q_dir.mkdir(parents=True, exist_ok=True)
                    shutil.copy(src, q_dir / f)

        # ── 3. SentencePiece 토크나이저 저장 ────────────────────
        tok = MarianTokenizer.from_pretrained(hf_id)
        tok.save_pretrained(str(tok_dir))
        _copy_spm_files(fp32_dir, tok_dir)
        del tok
        gc.collect()

        # ── 4. FP32 임시 파일 정리 ──────────────────────────────
        shutil.rmtree(fp32_dir, ignore_errors=True)

        # ── 5. ZIP 패키징 ────────────────────────────────────────
        KEEP_EXTS  = {'.onnx', '.spm'}
        KEEP_NAMES = {'tokenizer_config.json', 'config.json', 'vocab.json'}

        ZIP_DIR.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
            for f in q_dir.rglob("*"):
                if not f.is_file():
                    continue
                if f.suffix in KEEP_EXTS or f.name in KEEP_NAMES:
                    # _quantized 접미사 잔여물 제거
                    arcname = str(f.relative_to(q_dir)).replace("_quantized", "")
                    zf.write(f, arcname)

        size_mb = zip_path.stat().st_size / 1024 / 1024
        print(f"  [완료] {name:<8}  ZIP {size_mb:.0f}MB")

        # 양자화 디렉토리 정리
        shutil.rmtree(q_dir, ignore_errors=True)
        return True

    except Exception as e:
        print(f"  [실패] {name:<8}  {e}")
        shutil.rmtree(fp32_dir, ignore_errors=True)
        shutil.rmtree(q_dir, ignore_errors=True)
        if zip_path.exists():
            zip_path.unlink()
        return False


def main():
    if not _check_deps():
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    ZIP_DIR.mkdir(parents=True, exist_ok=True)
    print(f"\nOPUS-MT → ONNX INT8  (optimum)\n{'─'*50}")

    results = {name: convert_model(name, hf_id) for name, hf_id in MODELS.items()}

    ok    = sum(results.values())
    total = len(results)
    print(f"\n{'─'*50}")
    print(f"결과: {ok}/{total} 성공")
    for name, success in results.items():
        print(f"  {'✓' if success else '✗'} {name}")

    if ok > 0:
        total_mb = sum(
            f.stat().st_size for f in ZIP_DIR.glob("*.zip")
        ) / 1024 / 1024
        print(f"\n총 ZIP 크기: {total_mb:.0f}MB  (언어쌍당 평균 {total_mb/ok:.0f}MB)")


if __name__ == "__main__":
    main()
