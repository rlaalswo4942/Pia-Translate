import 'dart:async';
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

  // ── 초기 전체 모델 다운로드 상태 ─────────────────────────────
  bool                  isInitialSetup    = false;
  int                   setupModelTotal   = kRequiredModels.length;
  int                   setupModelDone    = 0;
  List<String>          setupFailedModels = [];
  Map<String, String>   setupErrorLog     = {}; // 모델별 실제 에러 메시지

  VoiceState voiceState = VoiceState.idle;
  OcrState   ocrState   = OcrState.idle;

  bool get isRecording  => voiceState == VoiceState.recording;
  bool get isOcrRunning => ocrState   == OcrState.processing;
  bool get isBusy       => isTranslating || isDownloading || isRecording || isOcrRunning || isInitialSetup;

  // 텍스트 필드 동기화 콜백 (화면에서 등록)
  void Function(String)? onSttText;

  // 현재 입력 유형 추적 (데이터 수집용)
  String _currentInputType = 'text';

  int autoRetryRound = 0; // 자동 재시도 누적 횟수

  // ── 앱 최초 실행 시 전체 모델 일괄 다운로드 ──────────────────
  Future<void> initAllModels() async {
    autoRetryRound = 0;
    final mm = ModelManager.instance;
    final checks = await Future.wait(kRequiredModels.map(mm.isDownloaded));
    final needed = [
      for (int i = 0; i < kRequiredModels.length; i++)
        if (!checks[i]) kRequiredModels[i],
    ];
    if (needed.isEmpty) return;
    autoRetryRound = 0;
    await _downloadModels(mm, needed);
  }

  // 수동 재시도 버튼 핸들러 (자동 재시도 횟수 초기화 후 재개)
  Future<void> retryFailedModels() async {
    autoRetryRound = 0;
    final mm      = ModelManager.instance;
    final toRetry = List<String>.from(setupFailedModels);
    setupFailedModels = [];
    setupModelDone    = setupModelTotal - toRetry.length;
    notifyListeners();
    await _downloadModels(mm, toRetry);
  }

  Future<void> _downloadModels(ModelManager mm, List<String> needed) async {
    isInitialSetup  = true;
    setupModelTotal = kRequiredModels.length;
    setupModelDone  = kRequiredModels.length - needed.length;
    setupFailedModels = [];
    setupErrorLog     = {};
    notifyListeners();

    final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      notifyListeners();
    });

    mm.onProgress = (name, prog) {
      downloadStatus   = '$name 다운로드 중...';
      downloadProgress = prog;
    };

    for (final name in needed) {
      try {
        await mm.downloadModel(name);
      } catch (e) {
        setupFailedModels.add(name);
        setupErrorLog[name] = e.toString();
      }
      setupModelDone++;
    }

    timer.cancel();
    mm.onProgress  = null;
    downloadStatus = '';

    if (setupFailedModels.isEmpty) {
      isInitialSetup = false;
      notifyListeners();
      // 현재 언어쌍 세션 사전 로드 — 첫 번역을 즉시 응답 가능하도록 warm-up
      _preloadCurrentSessions();
      return;
    }

    // 실패 시: 자동 재시도 (최대 20회, 3초 대기)
    // 20회 초과 시에만 수동 재시도 버튼 표시
    autoRetryRound++;
    if (autoRetryRound <= 20) {
      downloadStatus = '재시도 중... ($autoRetryRound/20)';
      notifyListeners();
      await Future.delayed(const Duration(seconds: 3));

      final toRetry = List<String>.from(setupFailedModels);
      setupModelDone = setupModelTotal - toRetry.length;
      await _downloadModels(mm, toRetry);
    } else {
      // 20회 모두 실패 → 수동 버튼 표시
      notifyListeners();
    }
  }


  // ── 현재 언어쌍 세션 사전 로드 ──────────────────────────────────
  void _preloadCurrentSessions() {
    final route = translationRoute(_src.code, _dst.code);
    for (final modelName in route) {
      ModelManager.instance.modelPath(modelName).then((dir) {
        tr.preloadSessions(dir);
      });
    }
  }

  // ── 언어 전환 ─────────────────────────────────────────────────
  void swapLanguages() {
    final tmp  = _src; _src = _dst; _dst = tmp;
    final tmpT = inputText; inputText = outputText; outputText = tmpT;
    recognizedText = '';
    ocrText        = '';
    ocrImagePath   = '';
    notifyListeners();
    _preloadCurrentSessions();
  }

  void setSrc(Language l) {
    if (l.code == _dst.code) { swapLanguages(); return; }
    _src = l;
    notifyListeners();
    _preloadCurrentSessions();
  }

  void setDst(Language l) {
    if (l.code == _src.code) { swapLanguages(); return; }
    _dst = l;
    notifyListeners();
    _preloadCurrentSessions();
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

    // 초기 설치 중이면 대기
    if (isInitialSetup) {
      errorMessage = '모델 다운로드 중입니다. 완료 후 번역하세요.';
      notifyListeners();
      return;
    }

    // 필요한 모델이 없으면 에러 (네트워크 문제로 초기 다운로드 실패한 경우)
    final mm    = ModelManager.instance;
    final route = translationRoute(_src.code, _dst.code);
    for (final model in route) {
      if (!await mm.isDownloaded(model)) {
        errorMessage = '[$model] 모델이 준비되지 않았습니다.\n'
            '네트워크를 확인 후 앱을 재시작해주세요.';
        notifyListeners();
        return;
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

  // ── 음성 인식 ─────────────────────────────────────────────────
  Future<void> toggleRecording(BuildContext context) async {
    if (voiceState == VoiceState.recording) {
      await _stopRecording(context);
    } else if (voiceState == VoiceState.idle) {
      await _startRecording(context);
    }
  }

  Future<void> _startRecording(BuildContext context) async {
    final stt = SttService.instance;
    if (!stt.isModelLoaded) {
      voiceState       = VoiceState.downloadingModel;
      downloadStatus   = '음성 모델 준비 중...';
      downloadProgress = 0.0;
      notifyListeners();
      Timer? sttTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        notifyListeners();
      });
      try {
        await stt.ensureModel(onProgress: (prog) {
          downloadProgress = prog;
          downloadStatus   = '음성 모델 다운로드 ${(prog * 100).round()}%';
        });
      } catch (e) {
        errorMessage = '음성 모델 다운로드 실패: $e';
        voiceState   = VoiceState.idle;
        sttTimer.cancel();
        notifyListeners();
        return;
      }
      sttTimer.cancel();
    }

    inputText         = '';
    recognizedText    = '';
    ocrText           = '';
    outputText        = '';
    errorMessage      = null;
    _currentInputType = 'voice';
    voiceState        = VoiceState.recording;
    notifyListeners();

    await stt.startListening(
      langCode: _src.code,
      onPartial: (text) {
        inputText = text;
        onSttText?.call(text);
        notifyListeners();
      },
      onResult: (text) {
        final normalized = TextNormalizer.normalize(text, langCode: _src.code);
        inputText      = normalized;
        recognizedText = normalized;
        onSttText?.call(normalized);
        voiceState = VoiceState.idle;
        notifyListeners();
        if (normalized.isNotEmpty) runTranslation(context);
      },
    );
  }

  Future<void> _stopRecording(BuildContext context) async {
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
    SttService.instance.dispose();
    super.dispose();
  }
}
