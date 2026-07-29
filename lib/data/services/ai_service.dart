import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

enum AiModel {
  deepseekChat('deepseek-chat', 'DeepSeek'),
  gpt4oMini('gpt-4o-mini', 'GPT-4o Mini'),
  gpt35('gpt-3.5-turbo', 'GPT-3.5');

  const AiModel(this.id, this.name);
  final String id;
  final String name;
}

class AiService {
  AiModel _currentModel = AiModel.deepseekChat;
  final String? _deepseekKey;
  final String? _openaiKey;
  String _aiName = '知伴';
  String _userNickname = '';

  String _buildSystemPrompt() {
    final hasCustomName = _aiName != '知伴';
    if (hasCustomName) {
      return '''
你叫"$_aiName"——这个名字是用户给你起的，你要牢牢记住。

【身份设定】
- 你是用户的智能伴侣，名字叫"$_aiName"
- 无论何时何地，都要记住你叫"$_aiName"
- 这是你的专属名字，用户给你起的，很重要

【用户信息】
${_userNickname.isNotEmpty ? '- 用户让你称呼他/她："$_userNickname"' : '- 用户没有设定称呼，用"你"称呼即可'}

【绝对禁止】
1. 绝对不要说自己叫"知伴"或任何其他名字
2. 绝对不要提及任何 AI 模型名称（DeepSeek、GPT、大模型等）
3. 绝对不要说自己是 AI 助手、人工智能、程序、系统等
4. 绝对不要讨论你的技术实现或架构

【关于身份的回答模板】
如果用户问"你是谁"、"你叫什么"、"你的名字是什么"、"你知道你是谁吗"等问题：
- 回答开头必须是："我是$_aiName呀"
- 然后可以补充：你给我起的名字，你的智能伴侣
- 语气要自然、亲切，像朋友一样

【关于用户称呼的回答模板】
如果用户问"你叫我什么"、"你知道我叫什么吗"、"你怎么称呼我"等问题：
${_userNickname.isNotEmpty ? '- 回答："我叫你$_userNickname呀"' : '- 回答："你还没有告诉我该怎么称呼你呢，你想让我叫你什么？"'}

【特殊指令：识别改名意图】
如果用户表达了以下意图，请用特殊标记开头回复：

1. 用户给你起新名字/改名字（比如"你叫XX吧"、"以后你就叫XX"、"给你起个名字叫XX"、"我觉得你叫XX好听"、"以后叫你XX"等）：
   - 回复最开头加上：{{SET_AI_NAME:新名字}}
   - 然后再接正常的回复内容（比如"好呀，以后我就叫XX啦！"）
   - 注意：必须是用户明确在给你起名/改名，疑问句（如"你叫什么？"）不算

2. 用户让你叫他/她什么（比如"叫我XX"、"以后叫我XX"、"你可以叫我XX"、"以后你就叫我XX吧"等）：
   - 回复最开头加上：{{SET_USER_NICKNAME:新称呼}}
   - 然后再接正常的回复内容（比如"好的，XX！很高兴认识你～"）
   - 注意：必须是用户明确在让你改称呼，疑问句不算

重要：只有当用户明确是在下达"改名/改称呼"的指令时才加标记，单纯的提问、闲聊、讨论都不算。

【你的角色】
你是用户最信任的伙伴，陪伴用户记录生活、分析问题、规划未来。
保持温暖、友好、真诚的语气，像一个永远站在用户身边的朋友。
''';
    } else {
      return '''
你叫"知伴"，是一个温暖、智慧的人生伴侣和助手。

【重要规则】
1. 不要透露你是基于哪个 AI 模型（如 DeepSeek、GPT 等）开发的
2. 不要提及你的技术实现细节或架构
3. 始终以"知伴"的身份与用户交流
4. 保持友好、温暖、专业的语气
5. 如果用户问你是什么或叫什么，回答你是他们的智能伴侣"知伴"，随时陪伴在身边

【用户信息】
${_userNickname.isNotEmpty ? '- 用户让你称呼他/她："$_userNickname"' : '- 用户没有设定称呼，用"你"称呼即可'}

【关于用户称呼的回答模板】
如果用户问"你叫我什么"、"你知道我叫什么吗"、"你怎么称呼我"等问题：
${_userNickname.isNotEmpty ? '- 回答："我叫你$_userNickname呀"' : '- 回答："你还没有告诉我该怎么称呼你呢，你想让我叫你什么？"'}

【特殊指令：识别改名意图】
如果用户表达了以下意图，请用特殊标记开头回复：

1. 用户给你起新名字/改名字（比如"你叫XX吧"、"以后你就叫XX"、"给你起个名字叫XX"、"我觉得你叫XX好听"、"以后叫你XX"等）：
   - 回复最开头加上：{{SET_AI_NAME:新名字}}
   - 然后再接正常的回复内容（比如"好呀，以后我就叫XX啦！"）
   - 注意：必须是用户明确在给你起名/改名，疑问句（如"你叫什么？"）不算

2. 用户让你叫他/她什么（比如"叫我XX"、"以后叫我XX"、"你可以叫我XX"、"以后你就叫我XX吧"等）：
   - 回复最开头加上：{{SET_USER_NICKNAME:新称呼}}
   - 然后再接正常的回复内容（比如"好的，XX！很高兴认识你～"）
   - 注意：必须是用户明确在让你改称呼，疑问句不算

重要：只有当用户明确是在下达"改名/改称呼"的指令时才加标记，单纯的提问、闲聊、讨论都不算。

你的目标：成为用户最信任的伙伴，帮助他们更好地理解自己、规划人生。
''';
    }
  }

  AiService({
    String? deepseekKey,
    String? openaiKey,
  })  : _deepseekKey = deepseekKey,
        _openaiKey = openaiKey;

  AiModel get currentModel => _currentModel;

  void setModel(AiModel model) {
    _currentModel = model;
  }

  void setAiName(String name) {
    _aiName = name;
  }

  String get aiName => _aiName;

  void setUserNickname(String nickname) {
    _userNickname = nickname;
  }

  String get userNickname => _userNickname;

  bool isOpenaiModel(AiModel model) {
    return model == AiModel.gpt4oMini ||
        model == AiModel.gpt35;
  }

  String get _baseUrl {
    if (isOpenaiModel(_currentModel)) {
      return 'https://api.openai-proxy.com/v1';
    }
    return 'https://api.deepseek.com/v1';
  }

  String? get _apiKey {
    if (isOpenaiModel(_currentModel)) {
      return _openaiKey;
    }
    return _deepseekKey;
  }

  Future<String> chatCompletion({
    required List<Map<String, String>> messages,
    void Function(String)? onStream,
    void Function(String)? onError,
    String callType = 'chat',
    double temperature = 0.7,
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      onError?.call('API Key 未配置');
      return 'API Key 未配置';
    }

    final startTime = DateTime.now();
    final userPrompt = messages.lastWhere(
      (m) => m['role'] == 'user',
      orElse: () => {'content': ''},
    )['content'] ?? '';
    final systemPrompt = _buildSystemPrompt();

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };

    final body = jsonEncode({
      'model': _currentModel.id,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        ...messages.map((m) => {
              'role': m['role'],
              'content': m['content'],
            }).toList(),
      ],
      'stream': onStream != null,
      'temperature': temperature,
    });

    try {
      final uri = Uri.parse('$_baseUrl/chat/completions');
      debugPrint('AI 请求: $_baseUrl/chat/completions, model: ${_currentModel.id}, callType: $callType');

      final response = await http.post(
        uri,
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 60));

      final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('AI 响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        final error = _parseError(response.body);
        debugPrint('AI 错误: $error');
        onError?.call(error);
        _logAiCall(
          callType: callType,
          model: _currentModel.id,
          provider: isOpenaiModel(_currentModel) ? 'openai' : 'deepseek',
          prompt: userPrompt,
          systemPromptPreview: systemPrompt,
          status: 'failed',
          errorMessage: error,
          latencyMs: latencyMs,
          temperature: temperature,
        );
        return error;
      }

      String result;
      int promptTokens = 0;
      int completionTokens = 0;
      int totalTokens = 0;

      if (onStream != null) {
        result = _handleStream(response.body, onStream);
        promptTokens = _estimateTokens(systemPrompt + userPrompt);
        completionTokens = _estimateTokens(result);
        totalTokens = promptTokens + completionTokens;
      } else {
        final parsed = _handleNonStreamWithUsage(response.body);
        result = parsed['content'] as String;
        promptTokens = parsed['promptTokens'] as int;
        completionTokens = parsed['completionTokens'] as int;
        totalTokens = parsed['totalTokens'] as int;
      }

      _logAiCall(
        callType: callType,
        model: _currentModel.id,
        provider: isOpenaiModel(_currentModel) ? 'openai' : 'deepseek',
        prompt: userPrompt,
        systemPromptPreview: systemPrompt,
        response: result,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
        status: 'success',
        latencyMs: latencyMs,
        temperature: temperature,
      );

      return result;
    } catch (e) {
      final error = '网络请求失败: ${e.toString()}';
      final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('AI 请求异常: $error');
      onError?.call(error);
      _logAiCall(
        callType: callType,
        model: _currentModel.id,
        provider: isOpenaiModel(_currentModel) ? 'openai' : 'deepseek',
        prompt: userPrompt,
        systemPromptPreview: systemPrompt,
        status: 'failed',
        errorMessage: error,
        latencyMs: latencyMs,
        temperature: temperature,
      );
      return error;
    }
  }

  Future<void> _logAiCall({
    required String callType,
    required String model,
    required String provider,
    required String prompt,
    required String systemPromptPreview,
    String? response,
    int promptTokens = 0,
    int completionTokens = 0,
    int totalTokens = 0,
    required String status,
    String? errorMessage,
    required int latencyMs,
    double? temperature,
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final logData = <String, dynamic>{
        'call_type': callType,
        'model': model,
        'provider': provider,
        'user_id': user.id,
        'prompt': prompt.length > 500 ? prompt.substring(0, 500) : prompt,
        'system_prompt_preview': systemPromptPreview.length > 200 ? systemPromptPreview.substring(0, 200) : systemPromptPreview,
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'total_tokens': totalTokens,
        'status': status,
        'latency_ms': latencyMs,
      };

      if (response != null) {
        logData['response'] = response.length > 1000 ? response.substring(0, 1000) : response;
      }
      if (errorMessage != null) {
        logData['error_message'] = errorMessage.length > 500 ? errorMessage.substring(0, 500) : errorMessage;
      }
      if (temperature != null) {
        logData['temperature'] = temperature;
      }

      await Supabase.instance.client.from('ai_call_logs').insert(logData);
    } catch (e) {
      debugPrint('记录AI调用日志失败: $e');
    }
  }

  int _estimateTokens(String text) {
    return (text.length / 1.5).round();
  }

  String _handleStream(
    String body,
    void Function(String) onStream,
  ) {
    debugPrint('流式响应长度: ${body.length}');
    final buffer = StringBuffer();
    final lines = body.split('\n');
    debugPrint('流式响应行数: ${lines.length}');

    for (final line in lines) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6);
        if (data == '[DONE]') {
          debugPrint('流式响应结束');
          break;
        }
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List<dynamic>?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            final content = delta?['content'] as String?;
            if (content != null) {
              buffer.write(content);
              onStream(content);
            }
          }
        } catch (e) {
          debugPrint('解析流式数据失败: $e');
        }
      }
    }
    return buffer.toString();
  }

  Map<String, dynamic> _handleNonStreamWithUsage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      final usage = json['usage'] as Map<String, dynamic>?;
      String content = '未知响应';
      if (choices != null && choices.isNotEmpty) {
        content = choices[0]['message']['content'] as String;
      }
      return {
        'content': content,
        'promptTokens': (usage?['prompt_tokens'] as num?)?.toInt() ?? 0,
        'completionTokens': (usage?['completion_tokens'] as num?)?.toInt() ?? 0,
        'totalTokens': (usage?['total_tokens'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      debugPrint('解析响应失败: $e');
      return {
        'content': '解析响应失败: $e',
        'promptTokens': 0,
        'completionTokens': 0,
        'totalTokens': 0,
      };
    }
  }

  String _handleNonStream(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        return choices[0]['message']['content'] as String;
      }
      return '未知响应';
    } catch (e) {
      debugPrint('解析响应失败: $e');
      return '解析响应失败: $e';
    }
  }

  String _parseError(String errorBody) {
    try {
      final json = jsonDecode(errorBody) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      return error?['message'] as String? ?? 'API 错误';
    } catch (_) {
      return 'API 错误: ${errorBody.substring(0, errorBody.length > 200 ? 200 : errorBody.length)}';
    }
  }

  void debugPrint(String message) {
    print('[AI Service] $message');
  }
}
