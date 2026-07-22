import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/agent_service.dart';
import '../../../data/services/ai_service.dart';
import '../../../data/services/logging_service.dart';
import '../../../data/services/speech_service.dart';
import '../../../providers/ai_provider.dart';
import '../../../providers/auth_provider.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isGenerating = false;
  bool _hasLoaded = false;
  bool _isRecording = false;
  String _interimText = '';
  LoggingService? _loggingService;
  StreamSubscription? _speechTextSub;
  StreamSubscription? _speechStatusSub;

  String _aiName = '知伴';
  String? _aiAvatarUrl;
  String _userNickname = '';

  // 分页加载
  static const int _pageSize = 20;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;

  // 搜索
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loggingService = LoggingService();
    _loadSettings();
    _scrollController.addListener(_onScroll);
    _speechTextSub = SpeechService.textStream.listen((text) {
      setState(() {
        _interimText = text;
        _messageController.text = text;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: text.length),
        );
      });
    });
    _speechStatusSub = SpeechService.statusStream.listen((recording) {
      setState(() {
        _isRecording = recording;
      });
    });
  }

  /// 调用后端 AI 意图检测 API
  /// 返回意图类型和值 {'intent': 'SET_AI_NAME'|'SET_USER_NICKNAME'|'NONE', 'value': ''}
  Future<Map<String, String>> _detectIntent(String message) async {
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8081/api/detect-intent'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': message}),
      );
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'intent': (result['intent'] as String?)?.trim() ?? 'NONE',
          'value': (result['value'] as String?)?.trim() ?? '',
        };
      }
    } catch (e) {
      debugPrint('意图检测失败: $e');
    }
    return {'intent': 'NONE', 'value': ''};
  }

  Future<void> _loadSettings() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('ai_name, ai_avatar_url, nickname')
          .eq('id', user.id)
          .single();

      if (response != null) {
        setState(() {
          _aiName = (response['ai_name'] as String?) ?? '知伴';
          _aiAvatarUrl = response['ai_avatar_url'] as String?;
          _userNickname = (response['nickname'] as String?) ?? '';
        });
        context.read<AiProvider>().setAiName(_aiName);
        context.read<AiProvider>().setUserNickname(_userNickname);
      }
    } catch (e) {
      debugPrint('加载设置失败: $e');
    }
  }

  Future<void> _saveSettings({String? aiName, String? aiAvatarUrl, String? nickname}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            if (aiName != null) 'ai_name': aiName,
            if (aiAvatarUrl != null) 'ai_avatar_url': aiAvatarUrl,
            if (nickname != null) 'nickname': nickname,
          })
          .eq('id', user.id);
    } catch (e) {
      debugPrint('保存设置失败: $e');
      if (e.toString().contains('column') && e.toString().contains('does not exist')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('保存失败：需要在数据库中添加字段。请联系管理员。'),
            backgroundColor: AppColors.stateError,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// 处理AI回复中的特殊指令标记
  /// 返回清理后的回复内容
  String _processAiResponse(String content) {
    var cleaned = content;
    var hasCommand = false;

    // 检测设置AI名称的标记：{{SET_AI_NAME:新名字}}
    final aiNameMatch = RegExp(r'\{\{SET_AI_NAME:(.+?)\}\}').firstMatch(cleaned);
    if (aiNameMatch != null) {
      final newName = aiNameMatch.group(1)?.trim();
      if (newName != null && newName.isNotEmpty) {
        setState(() => _aiName = newName);
        _saveSettings(aiName: newName);
        context.read<AiProvider>().setAiName(newName);
        cleaned = cleaned.replaceFirst(aiNameMatch.group(0)!, '');
        hasCommand = true;
      }
    }

    // 检测设置用户昵称的标记：{{SET_USER_NICKNAME:新称呼}}
    final nicknameMatch = RegExp(r'\{\{SET_USER_NICKNAME:(.+?)\}\}').firstMatch(cleaned);
    if (nicknameMatch != null) {
      final newNickname = nicknameMatch.group(1)?.trim();
      if (newNickname != null && newNickname.isNotEmpty) {
        setState(() => _userNickname = newNickname);
        _saveSettings(nickname: newNickname);
        context.read<AiProvider>().setUserNickname(newNickname);
        cleaned = cleaned.replaceFirst(nicknameMatch.group(0)!, '');
        hasCommand = true;
      }
    }

    // 如果有命令标记，清理开头可能多余的换行和空格
    if (hasCommand) {
      cleaned = cleaned.trimLeft();
    }

    return cleaned;
  }

  void _ensureLoaded() {
    if (!_hasLoaded) {
      _hasLoaded = true;
      Future.microtask(() {
        try {
          _loadMessages();
        } catch (e, stackTrace) {
          debugPrint('加载消息失败: $e');
          debugPrint('堆栈: $stackTrace');
        }
      });
    }
  }

  @override
  void dispose() {
    _speechTextSub?.cancel();
    _speechStatusSub?.cancel();
    SpeechService.stopRecording();
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _getUserName() {
    if (_userNickname.isNotEmpty) {
      return _userNickname;
    }
    final auth = context.read<AuthProvider>();
    final username = auth.profile?.username;
    if (username != null && username.isNotEmpty) {
      return username;
    }
    final email = auth.user?.email;
    if (email != null && email.isNotEmpty && email.contains('@')) {
      return email.split('@').first;
    }
    return '朋友';
  }

  String _getWelcomeText() {
    final name = _getUserName();
    return '早上好，$name。今天有什么想聊聊的？可以跟我分享任何事，我帮你记住和分析。';
  }

  /// 初始加载：获取最新的 _pageSize 条消息
  Future<void> _loadMessages() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': _getWelcomeText(),
          'tags': <String>[],
          'isError': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      });
      return;
    }

    try {
      // 按时间倒序获取最新的 _pageSize 条，然后反转为正序
      final response = await Supabase.instance.client
          .from('messages')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (response is List && response.isNotEmpty) {
        final reversed = response.reversed.toList();
        for (final msg in reversed) {
          final role = msg['role'] as String?;
          final content = msg['content'] as String?;
          if (role != null && content != null) {
            _messages.add({
              'role': role,
              'content': content,
              'tags': <String>[],
              'isError': false,
              'created_at': msg['created_at'] as String?,
            });
          }
        }
        _hasMoreMessages = response.length >= _pageSize;
      } else {
        _messages.add({
          'role': 'assistant',
          'content': _getWelcomeText(),
          'tags': <String>[],
          'isError': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      await _loggingService?.log(
        userId: user.id,
        operationType: OperationType.message_load,
        targetTable: 'messages',
        status: OperationStatus.success,
        message: '加载 ${_messages.length} 条消息',
        responseData: {'count': _messages.length},
      );
    } catch (e) {
      await _loggingService?.log(
        userId: user.id,
        operationType: OperationType.message_load,
        targetTable: 'messages',
        status: OperationStatus.failed,
        message: '加载消息失败',
        errorDetails: e.toString(),
      );

      _messages.add({
        'role': 'assistant',
        'content': _getWelcomeText(),
        'tags': <String>[],
        'isError': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    setState(() {});
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  /// 加载更多：往上滑动时加载更早的消息
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _messages.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoadingMore = true);

    // 保存当前滚动位置
    final oldMaxScroll = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldOffset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;

    try {
      final oldestCreatedAt = _messages.first['created_at'] as String?;
      if (oldestCreatedAt == null) {
        _hasMoreMessages = false;
        return;
      }

      final response = await Supabase.instance.client
          .from('messages')
          .select()
          .eq('user_id', user.id)
          .lt('created_at', oldestCreatedAt)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (response is List && response.isNotEmpty) {
        final reversed = response.reversed.toList();
        final newMessages = <Map<String, dynamic>>[];
        for (final msg in reversed) {
          final role = msg['role'] as String?;
          final content = msg['content'] as String?;
          if (role != null && content != null) {
            newMessages.add({
              'role': role,
              'content': content,
              'tags': <String>[],
              'isError': false,
              'created_at': msg['created_at'] as String?,
            });
          }
        }

        setState(() {
          _messages.insertAll(0, newMessages);
        });

        // 保持滚动位置：新内容加在顶部，需要向下滚动补偿
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final newMaxScroll = _scrollController.position.maxScrollExtent;
            _scrollController.jumpTo(oldOffset + (newMaxScroll - oldMaxScroll));
          }
        });

        _hasMoreMessages = response.length >= _pageSize;
      } else {
        _hasMoreMessages = false;
      }
    } catch (e) {
      debugPrint('加载更多消息失败: $e');
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  /// 滚动监听：接近顶部时加载更多
  void _onScroll() {
    if (_scrollController.hasClients && !_isLoadingMore && _hasMoreMessages) {
      if (_scrollController.position.pixels <= 100) {
        _loadMoreMessages();
      }
    }
  }

  /// 解析消息的日期（年月日），用于分组判断
  DateTime? _parseMessageDate(String? createdAtStr) {
    if (createdAtStr == null) return null;
    try {
      final dt = DateTime.parse(createdAtStr);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {
      return null;
    }
  }

  /// 获取日期分组标签（显示用）
  String _getDateGroupLabel(String? createdAtStr) {
    if (createdAtStr == null) return '更早';
    try {
      final dt = DateTime.parse(createdAtStr).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final date = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(date).inDays;

      if (diff == 0) return '今天';
      if (diff == 1) return '昨天';
      if (diff < 7) return '本周';
      if (date.month == now.month && date.year == now.year) return '本月';
      return '${dt.year}年${dt.month}月';
    } catch (_) {
      return '更早';
    }
  }

  Future<String?> _saveMessage(String role, String content) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    try {
      final response = await Supabase.instance.client
          .from('messages')
          .insert({
            'user_id': user.id,
            'role': role,
            'content': content,
          })
          .select('id,created_at')
          .single();

      final messageId = response['id'] as String?;
      final createdAt = response['created_at'] as String?;

      // 更新本地消息的 created_at
      if (_messages.isNotEmpty && createdAt != null) {
        _messages.last['created_at'] = createdAt;
      }

      await _loggingService?.logMessageSave(
        userId: user.id,
        role: role,
        content: content,
        messageId: messageId,
        success: true,
      );

      return messageId;
    } catch (e) {
      debugPrint('保存消息失败: $e');

      await _loggingService?.logMessageSave(
        userId: user.id,
        role: role,
        content: content,
        success: false,
        error: e.toString(),
      );

      return null;
    }
  }

  void _extractFactsAsync(String messageId, String userContent, {DateTime? messageCreatedAt}) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('📅 [Timeline] 用户未登录，跳过事实提取');
      return;
    }

    debugPrint('📅 [Timeline] 开始异步提取事实，messageId=$messageId');

    final aiService = context.read<AiProvider>().aiService;
    final agentService = AgentService(
      aiService: aiService,
      loggingService: _loggingService,
    );
    final createdAt = messageCreatedAt ?? DateTime.now();

    Future.microtask(() async {
      try {
        final result = await agentService.extractFacts(
          messageId: messageId,
          userId: user.id,
          userContent: userContent,
        );

        debugPrint('📅 [Timeline] 事实提取结果: success=${result.success}, data=${result.data != null}, factsCount=${result.data?.facts.length ?? 0}');

        if (!result.success) {
          debugPrint('📅 [Timeline] 事实提取失败: ${result.error}');
          return;
        }

        if (result.data == null) {
          debugPrint('📅 [Timeline] 事实提取返回空数据');
          return;
        }

        if (result.data!.facts.isEmpty) {
          debugPrint('📅 [Timeline] 未提取到任何事实，跳过时间线生成');
          return;
        }

        debugPrint('📅 [Timeline] 开始生成时间线事件...');
        final timelineResult = await agentService.generateTimelineEvent(
          messageId: messageId,
          userId: user.id,
          originalMessage: userContent,
          factGroup: result.data!.group,
          facts: result.data!.facts,
          messageCreatedAt: createdAt,
        );

        debugPrint('📅 [Timeline] 时间线生成结果: success=${timelineResult.success}, title=${timelineResult.data?.title ?? 'null'}');
        if (!timelineResult.success) {
          debugPrint('📅 [Timeline] 时间线生成失败: ${timelineResult.error}');
        }
      } catch (e, stackTrace) {
        debugPrint('📅 [Timeline] 异常: $e');
        debugPrint('📅 [Timeline] 堆栈: $stackTrace');
      }
    });
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    _messageController.clear();
    _interimText = '';

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final aiProvider = context.read<AiProvider>();

    final intentResult = await _detectIntent(text);
    final intent = intentResult['intent'] ?? 'NONE';
    final intentValue = intentResult['value'] ?? '';

    if (intent == 'SET_AI_NAME' && intentValue.isNotEmpty) {
      setState(() => _aiName = intentValue);
      aiProvider.setAiName(intentValue);
      await _saveSettings(aiName: intentValue);
    }

    if (intent == 'SET_USER_NICKNAME' && intentValue.isNotEmpty) {
      setState(() => _userNickname = intentValue);
      aiProvider.setUserNickname(intentValue);
      await _saveSettings(nickname: intentValue);
    }

    _isGenerating = true;

    setState(() {
      _messages.add({
        'role': 'user',
        'content': text,
        'tags': <String>[],
        'isError': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    });

    _scrollToBottom();

    final startTime = DateTime.now();
    final messageId = await _saveMessage('user', text);

    await _loggingService?.logMessageSend(
      userId: user.id,
      content: text,
      messageId: messageId,
      success: messageId != null,
    );

    if (messageId != null) {
      _extractFactsAsync(messageId, text, messageCreatedAt: startTime);
    }

    setState(() {
      _messages.add({
        'role': 'assistant',
        'content': '',
        'tags': <String>[],
        'isError': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    });

    String? errorMessage;

    try {
      await aiProvider.sendMessage(
        messages: _messages.where((m) => m['role'] != 'system').map((m) => {
              'role': m['role'] as String,
              'content': m['content'] as String,
            }).toList(),
        onStream: (token) {
          setState(() {
            _messages.last['content'] = (_messages.last['content'] ?? '') + token;
          });
          _scrollToBottom();
        },
        onError: (error) {
          errorMessage = error;
        },
      );
    } catch (e) {
      errorMessage = e.toString();
    }

    final aiDuration = DateTime.now().difference(startTime).inMilliseconds;

    if (errorMessage != null) {
      setState(() {
        _messages.last['content'] = 'AI 响应失败:\n\n$errorMessage';
        _messages.last['isError'] = true;
      });

      await _loggingService?.logAiResponse(
        userId: user.id,
        messageId: messageId,
        durationMs: aiDuration,
        success: false,
        error: errorMessage,
      );
    } else {
      final rawReply = _messages.last['content'] as String? ?? '';
      final cleanedReply = _processAiResponse(rawReply);

      setState(() {
        _messages.last['content'] = cleanedReply;
      });

      if (cleanedReply.isNotEmpty) {
        await _saveMessage('assistant', cleanedReply);
      }

      await _loggingService?.logAiResponse(
        userId: user.id,
        messageId: messageId,
        content: cleanedReply,
        durationMs: aiDuration,
        success: true,
      );
    }

    _isGenerating = false;
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.microtask(() {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已复制'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.stateSuccess,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
      ),
    );
  }

  void _toggleRecording() {
    if (!SpeechService.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('浏览器不支持语音识别，请使用 Chrome 浏览器'),
          backgroundColor: AppColors.stateError,
        ),
      );
      return;
    }

    if (_isRecording) {
      final text = SpeechService.stopRecording();
      setState(() {
        _isRecording = false;
        if (text.isNotEmpty) {
          _messageController.text = text;
          _messageController.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
        }
      });
    } else {
      _messageController.clear();
      _interimText = '';
      SpeechService.startRecording();
      setState(() {
        _isRecording = true;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final fileName = result.files.first.name;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已选择图片: $fileName（图片功能开发中）'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.stateInfo,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('选择图片失败: $e'),
          backgroundColor: AppColors.stateError,
        ),
      );
    }
  }

  /// 切换搜索模式
  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  /// 获取搜索结果
  List<Map<String, dynamic>> get _searchResults {
    if (_searchQuery.isEmpty) return [];
    final query = _searchQuery.toLowerCase();
    return _messages
        .asMap()
        .entries
        .where((e) {
          final content = (e.value['content'] as String?) ?? '';
          return content.toLowerCase().contains(query);
        })
        .map((e) => {
              'index': e.key,
              'role': e.value['role'],
              'content': e.value['content'],
              'created_at': e.value['created_at'],
            })
        .toList()
        .reversed
        .toList();
  }

  /// 跳转到指定消息
  void _jumpToMessage(int messageIndex) {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });

    // 计算目标位置（需要考虑日期分组头的高度）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // 粗略估算：每条消息约 80px，加上日期头
        double offset = 0;
        DateTime? lastDate;
        for (int i = 0; i < messageIndex && i < _messages.length; i++) {
          final msgDate = _parseMessageDate(_messages[i]['created_at'] as String?);
          if (msgDate != lastDate) {
            offset += 40; // 日期头高度
            lastDate = msgDate;
          }
          offset += 80; // 消息气泡大约高度
        }
        offset = offset.clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 构建显示项列表（日期头 + 消息）
  List<Map<String, dynamic>> _buildDisplayItems() {
    final items = <Map<String, dynamic>>[];
    DateTime? lastDate;

    for (int i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      final msgDate = _parseMessageDate(msg['created_at'] as String?);

      if (msgDate != lastDate) {
        final label = _getDateGroupLabel(msg['created_at'] as String?);
        items.add({'type': 'date_header', 'label': label});
        lastDate = msgDate;
      }

      items.add({'type': 'message', 'index': i, 'data': msg});
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            if (_isSearching) _buildSearchBar(),
            // 加载更多指示器
            if (_isLoadingMore)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            Expanded(
              child: _isSearching && _searchQuery.isNotEmpty
                  ? _buildSearchResults()
                  : _buildMessageList(),
            ),
            if (!_isSearching) _buildInputBar(),
          ],
        ),
      ),
    );
  }

  /// 消息列表（带日期分组）
  Widget _buildMessageList() {
    final displayItems = _buildDisplayItems();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: displayItems.length,
      itemBuilder: (context, index) {
        final item = displayItems[index];
        if (item['type'] == 'date_header') {
          return _buildDateHeader(item['label'] as String);
        }

        final msgIndex = item['index'] as int;
        final msg = item['data'] as Map<String, dynamic>;
        final isUser = msg['role'] == 'user';
        final isError = msg['isError'] == true;
        final tags = msg['tags'] as List<String>? ?? [];

        return _buildMessageBubble(
          content: msg['content'] ?? '',
          isUser: isUser,
          isError: isError,
          tags: tags,
          isGenerating: _isGenerating && msgIndex == _messages.length - 1 && !isUser && !isError,
        );
      },
    );
  }

  /// 日期分组头
  Widget _buildDateHeader(String label) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  /// 搜索栏
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      color: AppColors.bg,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            border: InputBorder.none,
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            hintText: '搜索聊天记录...',
            hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
            prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textTertiary),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(Icons.clear, size: 18, color: AppColors.textTertiary),
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() => _searchQuery = value);
          },
        ),
      ),
    );
  }

  /// 搜索结果列表
  Widget _buildSearchResults() {
    final results = _searchResults;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              '未找到相关消息',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        final content = result['content'] as String? ?? '';
        final role = result['role'] as String? ?? '';
        final createdAt = result['created_at'] as String?;
        final messageIndex = result['index'] as int;
        final isUser = role == 'user';

        // 高亮关键词
        final query = _searchQuery.toLowerCase();
        final lowerContent = content.toLowerCase();
        final matchIndex = lowerContent.indexOf(query);
        String preview = content;
        if (matchIndex >= 0) {
          final start = (matchIndex - 30).clamp(0, content.length);
          final end = (matchIndex + query.length + 30).clamp(0, content.length);
          preview = (start > 0 ? '...' : '') + content.substring(start, end) + (end < content.length ? '...' : '');
        }

        return GestureDetector(
          onTap: () => _jumpToMessage(messageIndex),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isUser ? Icons.person : Icons.smart_toy_outlined,
                      size: 14,
                      color: isUser ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isUser ? '我' : context.read<AiProvider>().aiName,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (createdAt != null)
                      Text(
                        _getDateGroupLabel(createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _buildHighlightedText(preview, _searchQuery),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 高亮搜索关键词
  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int currentIndex = 0;

    while (currentIndex < text.length) {
      final matchIndex = lowerText.indexOf(lowerQuery, currentIndex);
      if (matchIndex == -1) {
        spans.add(TextSpan(
          text: text.substring(currentIndex),
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
        ));
        break;
      }

      if (matchIndex > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, matchIndex),
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
        ));
      }

      spans.add(TextSpan(
        text: text.substring(matchIndex, matchIndex + query.length),
        style: TextStyle(
          fontSize: 14,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
          backgroundColor: AppColors.primaryTint,
          height: 1.4,
        ),
      ));

      currentIndex = matchIndex + query.length;
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  Widget _buildTopBar() {
    return Consumer<AiProvider>(
      builder: (context, aiProvider, child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: AppColors.bg,
          child: Row(
            children: [
              _buildAiAvatar(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      aiProvider.aiName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      aiProvider.userNickname.isNotEmpty
                          ? '你的${aiProvider.aiName}，随时在身边'
                          : '你的知伴，随时在身边',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleSearch,
            child: Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _isSearching ? AppColors.primaryTint : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _isSearching ? AppColors.primary.withOpacity(0.3) : AppColors.borderLight),
              ),
              child: Icon(
                _isSearching ? Icons.close : Icons.search,
                color: _isSearching ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
          GestureDetector(
            onTap: _showSettings,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Icon(Icons.settings_outlined, color: AppColors.textSecondary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAvatar() {
    if (_aiAvatarUrl != null && _aiAvatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          _aiAvatarUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(),
        ),
      );
    }
    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String newAiName = _aiName;
        String newNickname = _userNickname;

        return Container(
          margin: const EdgeInsets.all(16),
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '设置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: TextEditingController(text: newAiName),
                decoration: const InputDecoration(
                  labelText: 'AI 名字',
                  hintText: '输入 AI 的名字',
                ),
                onChanged: (value) => newAiName = value,
              ),
              const SizedBox(height: 16),

              TextField(
                controller: TextEditingController(text: newNickname),
                decoration: const InputDecoration(
                  labelText: '我的称呼',
                  hintText: '你希望 AI 怎么称呼你',
                ),
                onChanged: (value) => newNickname = value,
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _aiName = newAiName;
                          _userNickname = newNickname;
                        });
                        _saveSettings(aiName: newAiName, nickname: newNickname);
                        context.read<AiProvider>().setAiName(newAiName);
                        context.read<AiProvider>().setUserNickname(newNickname);
                        Navigator.pop(context);
                      },
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble({
    required String content,
    required bool isUser,
    required bool isError,
    required List<String> tags,
    bool isGenerating = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _buildAiAvatar(),
            ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(6),
                  bottomRight: isUser ? const Radius.circular(6) : const Radius.circular(20),
                ),
                boxShadow: isUser
                    ? [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]
                    : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (content.isNotEmpty)
                    isUser
                        ? SelectableText(
                            content,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                              height: 1.6,
                              fontWeight: FontWeight.w400,
                            ),
                            showCursor: true,
                            cursorColor: Colors.white,
                          )
                        : Container(
                            child: MarkdownBody(
                              data: content,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  fontSize: 15,
                                  color: AppColors.textPrimary,
                                  height: 1.6,
                                  fontWeight: FontWeight.w400,
                                ),
                                listBullet: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  height: 1.6,
                                ),
                                code: TextStyle(
                                  backgroundColor: AppColors.bgSecondary,
                                  color: AppColors.primary,
                                  fontSize: 13,
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: AppColors.bgSecondary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                blockquoteDecoration: BoxDecoration(
                                  color: AppColors.primaryTint,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border(
                                    left: BorderSide(color: AppColors.primary, width: 3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  if (isGenerating)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: SizedBox(
                        height: 4,
                        width: 24,
                        child: LinearProgressIndicator(
                          color: AppColors.primary,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    ),
                  if (!isUser && !isGenerating && content.isNotEmpty && !isError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GestureDetector(
                        onTap: () => _copyMessage(content),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy, size: 14, color: AppColors.primary),
                              const SizedBox(width: 5),
                              Text(
                                '复制',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 50),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: AppColors.bg,
      child: Column(
        children: [
          if (_isRecording)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.stateError.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.mic, color: AppColors.stateError, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _interimText.isEmpty ? '正在聆听...' : _interimText,
                      style: TextStyle(
                        fontSize: 14,
                        color: _interimText.isEmpty ? AppColors.textTertiary : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _toggleRecording,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.stateError,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '完成',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Icon(Icons.image_outlined, color: AppColors.textSecondary, size: 22),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onLongPress: _toggleRecording,
                onTap: _toggleRecording,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isRecording ? AppColors.stateError : AppColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _isRecording ? Colors.transparent : AppColors.borderLight),
                    boxShadow: _isRecording ? [BoxShadow(color: AppColors.stateError.withOpacity(0.3), blurRadius: 6)] : [],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic_outlined,
                    color: _isRecording ? Colors.white : AppColors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.borderLight),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
                  ),
                  child: TextField(
                    controller: _messageController,
                    textInputAction: TextInputAction.send,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      hintText: '输入消息...',
                      hintStyle: TextStyle(color: AppColors.textTertiary),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 22),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
