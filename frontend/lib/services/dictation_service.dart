import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';

class DictationService {
  static final DictationService _instance = DictationService._internal();
  factory DictationService() => _instance;
  DictationService._internal();

  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  String? _activeFieldId;
  bool _initialized = false;
  void Function()? _onDone;

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;
  String? get activeFieldId => _activeFieldId;

  /// Check if the browser likely supports Web Speech API (without initializing).
  static bool get webSpeechApiLikelyAvailable => kIsWeb;

  Future<bool> initialize() async {
    if (_initialized) {
      return _isAvailable;
    }
    try {
      _isAvailable = await _speechToText.initialize(
        onError: (error) {
          developer.log('SpeechToText error during init: ${error.errorMsg}',
              name: 'DictationService');
        },
        onStatus: (status) {
          developer.log('SpeechToText status: $status',
              name: 'DictationService');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            _activeFieldId = null;
            _onDone?.call();
            _onDone = null;
          }
        },
      );
      _initialized = true;
      developer.log('SpeechToText initialized: $_isAvailable',
          name: 'DictationService');
    } catch (e) {
      developer.log('SpeechToText init exception: $e',
          name: 'DictationService');
      _isAvailable = false;
      _initialized = true;
    }
    return _isAvailable;
  }

  Future<void> startListening({
    required String localeId,
    required String fieldId,
    required Function(String) onResult,
    required Function(String) onError,
    void Function()? onDone,
  }) async {
    if (_isListening && _activeFieldId != fieldId) {
      await stopListening();
    }

    _activeFieldId = fieldId;
    _isListening = true;
    _onDone = onDone;

    _speechToText.errorListener = (error) {
      _isListening = false;
      _activeFieldId = null;
      String errorMsg = error.errorMsg;
      if (errorMsg.contains('network')) {
        onError('Speech recognition unavailable — please type instead.');
      } else if (errorMsg.contains('not-allowed') ||
          errorMsg.contains('service-not-allowed')) {
        onError(
            'Microphone access denied. Please enable it in your browser settings.');
      } else {
        onError('Speech recognition error. Please try again.');
      }
    };

    await _speechToText.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: localeId,
      listenMode: stt.ListenMode.dictation,
      cancelOnError: false,
    );
  }

  Future<void> stopListening() async {
    await _speechToText.stop();
    _isListening = false;
    _activeFieldId = null;
  }
}
