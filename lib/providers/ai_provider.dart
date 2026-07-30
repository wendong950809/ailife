import 'package:flutter/foundation.dart';
import '../data/services/ai_service.dart';

class AiProvider extends ChangeNotifier {
  final AiService _aiService;

  AiModel _currentModel = AiModel.deepseekChat;
  bool _isLoading = false;
  String? _errorMessage;
  String _aiName = '知伴';
  String _userNickname = '';
  String _chatStyle = '自然';

  AiProvider({
    required AiService aiService,
  }) : _aiService = aiService;

  AiModel get currentModel => _currentModel;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  AiService get aiService => _aiService;
  String get aiName => _aiName;
  String get userNickname => _userNickname;
  String get chatStyle => _chatStyle;

  void setModel(AiModel model) {
    _currentModel = model;
    _aiService.setModel(model);
    notifyListeners();
  }

  void setAiName(String name) {
    _aiName = name;
    _aiService.setAiName(name);
    notifyListeners();
  }

  void setUserNickname(String nickname) {
    _userNickname = nickname;
    _aiService.setUserNickname(nickname);
    notifyListeners();
  }

  void setChatStyle(String style) {
    _chatStyle = style;
    _aiService.setChatStyle(style);
    notifyListeners();
  }

  Future<String> sendMessage({
    required List<Map<String, String>> messages,
    void Function(String)? onStream,
    void Function(String)? onError,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _aiService.chatCompletion(
      messages: messages,
      onStream: onStream,
      onError: (error) {
        _errorMessage = error;
        notifyListeners();
        onError?.call(error);
      },
    );

    _isLoading = false;
    notifyListeners();

    return result;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
