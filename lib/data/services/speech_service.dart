import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';

@JS('AiLifeSpeech.isSupported')
external bool _jsIsSupported();

@JS('AiLifeSpeech.start')
external void _jsStart(JSString lang, JSFunction onResult, JSFunction onError, JSFunction onEnd);

@JS('AiLifeSpeech.stop')
external void _jsStop();

class SpeechService {
  static bool _isRecording = false;
  static String _currentText = '';
  static final StreamController<String> _textController = StreamController.broadcast();
  static final StreamController<bool> _statusController = StreamController.broadcast();

  static bool get isRecording => _isRecording;
  static String get currentText => _currentText;
  static Stream<String> get textStream => _textController.stream;
  static Stream<bool> get statusStream => _statusController.stream;

  static bool get isSupported {
    if (!kIsWeb) return false;
    try {
      return _jsIsSupported();
    } catch (e) {
      return false;
    }
  }

  static void startRecording({
    void Function(String finalText, String interimText)? onResult,
    void Function(String error)? onError,
    void Function(String finalText)? onEnd,
  }) {
    if (!kIsWeb) return;
    _isRecording = true;
    _currentText = '';
    _statusController.add(true);

    try {
      _jsStart(
        'zh-CN'.toJS,
        ((JSString finalText, JSString interimText) {
          _currentText = '${finalText.toDart}${interimText.toDart}';
          _textController.add(_currentText);
          onResult?.call(finalText.toDart, interimText.toDart);
        }).toJS,
        ((JSString error) {
          _isRecording = false;
          _statusController.add(false);
          onError?.call(error.toDart);
        }).toJS,
        ((JSString finalText) {
          _isRecording = false;
          _currentText = finalText.toDart;
          _textController.add(_currentText);
          _statusController.add(false);
          onEnd?.call(finalText.toDart);
        }).toJS,
      );
    } catch (e) {
      _isRecording = false;
      _statusController.add(false);
      debugPrint('启动语音识别失败: $e');
    }
  }

  static String stopRecording() {
    _isRecording = false;
    _statusController.add(false);
    if (kIsWeb) {
      try {
        _jsStop();
      } catch (e) {
        debugPrint('停止语音识别失败: $e');
      }
    }
    return _currentText;
  }
}
