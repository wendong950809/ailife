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
import '../../../data/models/user_profile.dart';
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
          .select('ai_name, ai_avatar_url, nickname, chat_style')
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
        final savedStyle = (response['chat_style'] as String?) ?? '自然';
        context.read<AiProvider>().setChatStyle(savedStyle);
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

    // 检测设置生日的标记：{{SET_BIRTHDAY:yyyy-MM-dd}}
    final birthdayMatch = RegExp(r'\{\{SET_BIRTHDAY:(\d{4}-\d{2}-\d{2})\}\}').firstMatch(cleaned);
    if (birthdayMatch != null) {
      final dateStr = birthdayMatch.group(1)?.trim();
      if (dateStr != null) {
        try {
          final birthday = DateTime.parse(dateStr);
          context.read<AuthProvider>().updateProfile(birthday: birthday);
          cleaned = cleaned.replaceFirst(birthdayMatch.group(0)!, '');
          hasCommand = true;
        } catch (e) {
          debugPrint('解析生日日期失败: $e');
        }
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
              'id': msg['id'] as String?,
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
              'id': msg['id'] as String?,
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

    final createdAt = messageCreatedAt ?? DateTime.now();

    // 1. 直接生成时间线事件（不依赖 fact 提取，一次 AI 调用）
    _generateTimelineAsync(messageId, user.id, userContent, createdAt);

    // 2. 保留 fact 提取给记忆模块用（异步，不阻塞 timeline）
    debugPrint('📅 [Timeline] 开始异步提取事实，messageId=$messageId');
    final aiService = context.read<AiProvider>().aiService;
    final agentService = AgentService(
      aiService: aiService,
      loggingService: _loggingService,
    );

    Future.microtask(() async {
      try {
        final result = await agentService.extractFacts(
          messageId: messageId,
          userId: user.id,
          userContent: userContent,
        );
        debugPrint('📅 [Timeline] 事实提取结果: success=${result.success}, factsCount=${result.data?.facts.length ?? 0}');
      } catch (e, stackTrace) {
        debugPrint('📅 [Timeline] 事实提取异常: $e');
        debugPrint('📅 [Timeline] 堆栈: $stackTrace');
      }
    });
  }

  /// 独立的时间线生成方法（一次 AI 调用，不依赖 fact 提取）
  void _generateTimelineAsync(String messageId, String userId, String userContent, DateTime createdAt) {
    final aiService = context.read<AiProvider>().aiService;
    final agentService = AgentService(
      aiService: aiService,
      loggingService: _loggingService,
    );

    Future.microtask(() async {
      try {
        debugPrint('📅 [Timeline] 开始生成时间线事件...');
        final timelineResult = await agentService.generateTimelineEvent(
          messageId: messageId,
          userId: userId,
          originalMessage: userContent,
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

    // 将数据库返回的 id 存入本地消息，供删除等操作使用
    if (messageId != null && _messages.isNotEmpty) {
      _messages[_messages.length - 1]['id'] = messageId;
    }

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
        final aiMessageId = await _saveMessage('assistant', cleanedReply);
        if (aiMessageId != null && _messages.isNotEmpty) {
          _messages.last['id'] = aiMessageId;
        }
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

  /// 长按用户消息 → 确认删除
  /// 级联删除：用户消息 + AI回复 + timeline事件 + extracted_facts（自动级联）+ fact_groups（自动级联）
  void _confirmDeleteMessage(int msgIndex) {
    final msg = _messages[msgIndex];
    final userMessageId = msg['id'] as String?;

    // 无法删除没有 id 的消息（如欢迎语）
    if (userMessageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('该消息无法删除'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final content = (msg['content'] as String?) ?? '';
    final preview = content.length > 30 ? '${content.substring(0, 30)}...' : content;

    // 找到配对的 AI 回复（用户消息的下一条 assistant 消息）
    int? aiReplyIndex;
    if (msgIndex + 1 < _messages.length &&
        _messages[msgIndex + 1]['role'] == 'assistant') {
      aiReplyIndex = msgIndex + 1;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.stateError.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline, color: AppColors.stateError, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '删除这条对话',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '"$preview"',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('将同步删除：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    if (aiReplyIndex != null)
                      _buildDeleteItem('AI 的回复'),
                    _buildDeleteItem('时间线相关事件'),
                    _buildDeleteItem('提取的事实与记忆'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text('取消', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _deleteMessageCascade(msgIndex, userMessageId, aiReplyIndex);
                      },
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.stateError,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text('删除', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  /// 执行级联删除
  Future<void> _deleteMessageCascade(int userMsgIndex, String userMessageId, int? aiReplyIndex) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final aiMessageId = aiReplyIndex != null
        ? _messages[aiReplyIndex]['id'] as String?
        : null;

    final msgContent = _messages[userMsgIndex]['content'] ?? '';

    try {
      // 1. 先删除 timeline 中引用该消息的事件（FK 是 SET NULL，需手动删）
      await Supabase.instance.client
          .from('timeline')
          .delete()
          .eq('message_id', userMessageId);

      // 2. 删除 AI 回复消息（如果有 id）
      if (aiMessageId != null) {
        await Supabase.instance.client
            .from('messages')
            .delete()
            .eq('id', aiMessageId);
      }

      // 3. 删除用户消息（extracted_facts 和 fact_groups 会自动 CASCADE）
      await Supabase.instance.client
          .from('messages')
          .delete()
          .eq('id', userMessageId);

      // 4. 从本地列表中移除（先移除 AI 回复，再移除用户消息，注意索引顺序）
      setState(() {
        if (aiReplyIndex != null) {
          _messages.removeAt(aiReplyIndex);
        }
        _messages.removeAt(userMsgIndex);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已删除对话及相关记录'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.stateSuccess,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
          ),
        );
      }

      await _loggingService?.log(
        userId: user.id,
        operationType: OperationType.message_delete,
        targetTable: 'messages',
        status: OperationStatus.success,
        message: '删除消息: $msgContent',
        responseData: {
          'user_message_id': userMessageId,
          'ai_message_id': aiMessageId,
        },
      );
    } catch (e) {
      debugPrint('删除消息失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: AppColors.stateError,
          ),
        );
      }
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          msgIndex: msgIndex,
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
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
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                          : '你的${aiProvider.aiName}，随时在身边',
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

  Widget _buildUserAvatar() {
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    final avatarUrl = profile?.avatarUrl;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarUrl,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildDefaultUserAvatar(auth, profile),
        ),
      );
    }
    return _buildDefaultUserAvatar(auth, profile);
  }

  Widget _buildDefaultUserAvatar(AuthProvider auth, UserProfile? profile) {
    final email = auth.user?.email;
    final displayChar = profile?.username?.isNotEmpty == true
        ? profile!.username![0]
        : (email?.isNotEmpty == true ? email![0].toUpperCase() : '?');
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D26),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          displayChar,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildAiAvatar() {
    // 优先使用 AuthProvider 中的实时数据，回退到本地缓存
    final authAvatarUrl = context.read<AuthProvider>().profile?.aiAvatarUrl;
    final avatarUrl = authAvatarUrl ?? _aiAvatarUrl;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarUrl,
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
    int? msgIndex,
    bool isGenerating = false,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth * 0.72;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildAiAvatar(),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: GestureDetector(
              onLongPress: isUser && msgIndex != null
                  ? () => _confirmDeleteMessage(msgIndex)
                  : null,
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
                ),
                boxShadow: isUser
                    ? [BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))]
                    : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 1))],
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
                              height: 1.5,
                              fontWeight: FontWeight.w400,
                            ),
                          )
                        : MarkdownBody(
                            data: content,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                fontSize: 15,
                                color: AppColors.textPrimary,
                                height: 1.5,
                              ),
                              listBullet: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                height: 1.5,
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
                  if (isGenerating)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SizedBox(
                        height: 3,
                        width: 20,
                        child: LinearProgressIndicator(
                          color: AppColors.primary,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    ),
                  if (!isUser && !isGenerating && content.isNotEmpty && !isError)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: GestureDetector(
                        onTap: () => _copyMessage(content),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy, size: 12, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                '复制',
                                style: TextStyle(
                                  fontSize: 12,
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
          ),
          if (isUser)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _buildUserAvatar(),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final hasText = _messageController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(
          top: BorderSide(color: AppColors.borderLight.withOpacity(0.5), width: 0.5),
        ),
      ),
      child: Column(
        children: [
          if (_isRecording)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.stateError.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.stateError,
                      shape: BoxShape.circle,
                    ),
                  ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.stateError,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '完成',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 图片按钮
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: const Icon(Icons.image_outlined, color: AppColors.textTertiary, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              // 语音按钮
              GestureDetector(
                onLongPress: _toggleRecording,
                onTap: _toggleRecording,
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: _isRecording ? AppColors.stateError : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: _isRecording ? Colors.transparent : AppColors.borderLight),
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop_rounded : Icons.mic_none_rounded,
                    color: _isRecording ? Colors.white : AppColors.textTertiary,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 输入框（更优雅的圆角胶囊）
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 100, minHeight: 38),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderLight),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          textInputAction: TextInputAction.send,
                          keyboardType: TextInputType.multiline,
                          maxLines: null,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                            hintText: '说点什么...',
                            hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                          ),
                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          onSubmitted: (_) => _sendMessage(),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 发送按钮（有内容时高亮）
              GestureDetector(
                onTap: _sendMessage,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    gradient: hasText
                        ? const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: hasText ? null : AppColors.bgSecondary,
                    shape: BoxShape.circle,
                    boxShadow: hasText
                        ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
                        : null,
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: hasText ? Colors.white : AppColors.textTertiary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
