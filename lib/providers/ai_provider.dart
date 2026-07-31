import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/services/ai_service.dart';

class AiProvider extends ChangeNotifier {
  final AiService _aiService;

  AiModel _currentModel = AiModel.glm4Flash; // 默认用免费的智谱
  bool _isLoading = false;
  String? _errorMessage;
  String _aiName = '知伴';
  String _userNickname = '';
  String _chatStyle = '自然';
  bool _settingsLoaded = false;

  AiProvider({
    required AiService aiService,
  }) : _aiService = aiService {
    // 监听 auth 状态变化：当 session 恢复/用户登录时，自动加载 AI 设置
    // 解决 Web 端刷新页面时 session 异步恢复导致 loadSettings 被跳过的问题
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        loadSettings(force: true);
      }
    });
  }

  AiModel get currentModel => _currentModel;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  AiService get aiService => _aiService;
  String get aiName => _aiName;
  String get userNickname => _userNickname;
  String get chatStyle => _chatStyle;

  /// 从数据库加载 AI 设置（ai_name、nickname、chat_style、ai_model）
  /// 只加载一次，除非 force 为 true
  Future<void> loadSettings({bool force = false}) async {
    if (_settingsLoaded && !force) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('ai_name, nickname, chat_style, ai_model')
          .eq('id', user.id)
          .single();

      if (response != null) {
        _aiName = (response['ai_name'] as String?) ?? '知伴';
        _userNickname = (response['nickname'] as String?) ?? '';
        _chatStyle = (response['chat_style'] as String?) ?? '自然';

        _aiService.setAiName(_aiName);
        _aiService.setUserNickname(_userNickname);
        _aiService.setChatStyle(_chatStyle);

        final savedModelName = response['ai_model'] as String?;
        if (savedModelName != null && savedModelName.isNotEmpty) {
          try {
            final savedModel = AiModel.values.firstWhere(
              (m) => m.name == savedModelName,
            );
            _currentModel = savedModel;
            _aiService.setModel(savedModel);
          } catch (_) {
            // 找不到匹配的模型，保持默认
          }
        }

        _settingsLoaded = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载AI设置失败: $e');
    }
  }

  /// 将当前 AI 设置保存到数据库
  Future<void> saveSettings() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'ai_name': _aiName,
            'nickname': _userNickname,
            'chat_style': _chatStyle,
            'ai_model': _currentModel.name,
          })
          .eq('id', user.id);
    } catch (e) {
      debugPrint('保存AI设置失败: $e');
    }
  }

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
