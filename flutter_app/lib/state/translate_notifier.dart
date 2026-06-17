import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/config.dart';
import '../core/languages.dart';
import '../services/data_collector.dart';
import '../services/model_manager.dart';
import '../services/ocr_service.dart';
import '../services/stt_service.dart';
import '../services/text_normalizer.dart';
import '../services/tts_service.dart';
import '../services/translator.dart' as tr;

enum VoiceState { idle, downloadingModel, recording }
enum OcrState   { idle, processing }

/// 번역 화면 전체 상태 — UI와 완전히 분리된 순수 비즈니스 로직
class TranslateNotifier extends ChangeNotifier {
  Language _src = kSupportedLanguages[0]; // 한국어
  Language _dst = kSupportedLanguages[1]; // 영어

  Language get src => _src;
  Language get dst => _dst;

  String inputText      = '';
  String recognizedText = ''; // STT 인식 결과 (파란 카드)
  String ocrText        = ''; // OCR 인식 결과 (초록 카드)
  String ocrImagePath   = '';
  String outputText     = '';

  bool   isTranslating  = false;
  bool   isDownloading  = false;
  String downloadStatus    = '';
  double downloadProgress  = 0.0;
  String? errorMessage;

  VoiceState voiceState = VoiceState.idle;
  OcrState   ocrState   = OcrState.idle;

  bool get isRecording  => voiceState == VoiceState.recording;
  bool get isOcrRunning => ocrState   == OcrState.processing;
  bool get isBusy       => isTranslating || isDownloading || isRecording || isOcrRunning;

  // 텍스트 필드 동기화 콜백 (화면에서 등록)
  void Function(String)? onSttText;

  // 현재 입력 유형 추적 (데이터 수집용)
  String _currentInputType = 'text';

  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _resultSub;

  // ── 언어 전환 ─────────────────────────────────────────────────
  void swapLanguages() {
    final tmp  = _src; _src = _dst; _dst = tmp;
    final tmpT = inputText; inputText = outputText; outputText = tmpT;
    recognizedText = '';
    ocrText        = '';
    ocrImagePath   = '';
    notifyListeners();
  }

  void setSrc(Language l) {
    if (l.code == _dst.code) { swapLanguages(); return; }
    _src = l; notifyListeners();
  }

  void setDst(Language l) {
    if (l.code == _src.code) { swapLanguages(); return; }
    _dst = l; notifyListeners();
  }

  // ── 전체 초기화 ──────────────────────────────────────────────
  void clearAll(TextEditingController ctrl) {
    ctrl.clear();
    inputText      = '';
    recognizedText = '';
    ocrText        = '';
    ocrImagePath   = '';
    outputText     = '';
    errorMessage   = null;
    _currentInputType = 'text';
    notifyListeners();
  }

  // ── 번역 실행 ─────────────────────────────────────────────────
  Future<void> runTranslation(BuildContext context) async {
    if (inputText.trim().isEmpty) return;

    final mm    = ModelManager.instance;
    final route = translationRoute(_src.code, _dst.code);
    for (final model in route) {
      if (!await mm.isDownloaded(model)) {
        await _downloadTranslationModels(route, mm);
        break;
      }
    }

    isTranslating = true;
    errorMessage  = null;
    notifyListeners();

    try {
      outputText = await tr.translate(
        text:    inputText,
        srcLang: _src.code,
        dstLang: _dst.code,
      );

      // TTS 재생 (연결 시 자동 활성화)
      TtsService.instance.speak(outputText, _dst.code);

      // Pia 학습 데이터 수집
      await DataCollector.instance.record(
        inputType:      _currentInputType,
        srcLang:        _src.code,
        dstLang:        _dst.code,
        sourceText:     inputText,
        translatedText: outputText,
      );
    } catch (e) {
      errorMessage = '번역 오류: $e';
      outputText   = '';
    } finally {
      isTranslating = false;
      notifyListeners();
    }
  }

  Future<void> _downloadTranslationModels(
      List<String> models, ModelManager mm) async {
    isDownloading = true;
    notifyListeners();
    mm.onProgress = (name, prog) {
      downloadStatus   = '$name 다운로드 중...';
      downloadProgress = prog;
      notifyListeners();
    };
    try {
      await mm.ensureModels(models);
    } catch (e) {
      errorMessage = '모델 다운로드 실패: $e';
      notifyListeners();
    } finally {
      isDownloading    = false;
      mm.onProgress    = null;
      notifyListeners();
    }
  }

  // ── 음성 인식 ─────────────────────────────────────────────────
  Future<void> toggleRecording(BuildContext context) async {
    if (voiceState == VoiceState.recording) {
      await _stopRecording(context);
    } else if (voiceState == VoiceState.idle) {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final stt = SttService.instance;
    if (!stt.isModelLoaded) {
      voiceState       = VoiceState.downloadingModel;
      downloadStatus   = '음성 모델 준비 중...';
      downloadProgress = 0.0;
      notifyListeners();
      try {
        await stt.ensureModel(onProgress: (prog) {
          downloadProgress = prog;
          downloadStatus   = '음성 모델 다운로드 ${(prog * 100).round()}%';
          notifyListeners();
        });
      } catch (e) {
        errorMessage = '음성 모델 다운로드 실패: $e';
        voiceState   = VoiceState.idle;
        notifyListeners();
        return;
      }
    }

    inputText         = '';
    recognizedText    = '';
    ocrText           = '';
    outputText        = '';
    errorMessage      = null;
    _currentInputType = 'voice';
    voiceState        = VoiceState.recording;
    notifyListeners();

    final service = await stt.startListening();

    _partialSub = service.onPartial().listen((json) {
      final text = (jsonDecode(json)['partial'] as String?) ?? '';
      inputText = text;
      onSttText?.call(text);
      notifyListeners();
    });

    _resultSub = service.onResult().listen((json) {
      final text = (jsonDecode(json)['text'] as String?) ?? '';
      if (text.isNotEmpty) {
        inputText = text;
        onSttText?.call(text);
        notifyListeners();
      }
    });
  }

  Future<void> _stopRecording(BuildContext context) async {
    await _partialSub?.cancel();
    await _resultSub?.cancel();
    _partialSub = null;
    _resultSub  = null;
    await SttService.instance.stopListening();

    final normalized = TextNormalizer.normalize(inputText, langCode: _src.code);
    inputText      = normalized;
    recognizedText = normalized;
    onSttText?.call(normalized);
    voiceState = VoiceState.idle;
    notifyListeners();

    if (normalized.isNotEmpty) await runTranslation(context);
  }

  // ── OCR ───────────────────────────────────────────────────────
  Future<void> pickAndOcr(BuildContext context, ImageSource source) async {
    XFile? image;
    try {
      image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
      );
    } catch (e) {
      errorMessage = '이미지 접근 권한이 필요합니다: $e';
      notifyListeners();
      return;
    }
    if (image == null) return;

    ocrState          = OcrState.processing;
    _currentInputType = 'image';
    errorMessage      = null;
    notifyListeners();

    try {
      final rawText = await OcrService.instance.recognize(image.path, _src.code);
      if (rawText.isEmpty) {
        errorMessage = '이미지에서 텍스트를 찾지 못했습니다.';
        ocrState = OcrState.idle;
        notifyListeners();
        return;
      }

      final normalized = TextNormalizer.normalize(rawText, langCode: _src.code);
      ocrText        = normalized;
      ocrImagePath   = image.path;
      inputText      = normalized;
      recognizedText = '';
      onSttText?.call(normalized);
      ocrState = OcrState.idle;
      notifyListeners();

      if (normalized.isNotEmpty) await runTranslation(context);
    } catch (e) {
      errorMessage = 'OCR 오류: $e';
      ocrState     = OcrState.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _partialSub?.cancel();
    _resultSub?.cancel();
    super.dispose();
  }
}
