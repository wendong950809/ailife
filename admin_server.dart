import 'dart:io';
import 'dart:convert';

// ============================================
// AI Life 后台管理系统服务器
// ============================================

late String supabaseUrl;
late String serviceKey;
late String anonKey;
late String deepseekApiKey;

// 全局 HTTP 客户端，启用连接复用（关键性能优化）
final httpClient = HttpClient();

// 用户缓存：user_id -> profile data
Map<String, Map<String, dynamic>> _userCache = {};

const String factExtractionSystemPrompt = '''
你是信息抽取器，从用户消息中抽取最小事实单元，组织为事实组。

核心原则：
1. 只抽取不理解，不推理不猜测
2. 不做业务分类（目标/工作/家庭等交给第二层）
3. 成组输出，同一句话的事实归为一组
4. 不确定就跳过
5. 粒度统一：每种事实类型都有明确边界，不要越界

事实类型（仅9种）：
- action(name): 行为动作，只回答"发生了什么？"，不含人物/地点/时间。如"骑车"不是"陪女儿去公园骑车"
- person(name/role/relation): 明确身份的人。如"女儿"、"张三"、"老板"、"父亲"
- reference(type/value/resolved): 代词指向未知身份。如 type=person, value=她, resolved=false
- time(date/duration/frequency/milestone/relative): 时间信息。如"今天"、"两小时"、"每天"、"第一次"、"小时候"
- location(place/from/to): 地点信息。如"公司"、"北京"、"公园"
- emotion(feeling/trigger): 真实情绪，仅限基本情绪词。如"开心"、"难过"、"焦虑"、"放松"。不要"值得"、"应该"、"重要"等价值判断
- object(name): 对象物品，仅当 Action 无法完整表达时使用。如"自行车"、"合同"。若 Action="赚到第一笔利润"已完整，则不需要 Object="利润"
- intent(type/content): 意图类型，type 仅使用枚举值：request/question/plan/need/consult。content 只描述意图类型，不重复 Action 内容。如 type=plan, content=成立公司
- state(status): 状态描述。如"腰疼"、"脊椎有问题"、"身体不舒服"、"业务增长"

可信度规则：
- 1.0: 明确事实
- 0.8: 略有修饰
- 0.6: 暗示
- 0.4以下: 跳过

去重规则：
- 同一组内相同 fact_type + fact_key + fact_value 的事实只保留一个
- person 不要重复（如"女儿"出现两次只保留一次）
- Action 和 Intent 不要表达同一件事（Intent 描述意图类型，Action 描述具体行为）

格式约束：
- 输出必须是纯 JSON，不要 Markdown 代码块
- 无事实时输出：{"summary":"","facts":[]}
- summary 是事实摘要，不超过50字，只描述事实不做推理

示例1（"今天陪女儿去公园骑自行车"）：
{"summary":"今天陪女儿去公园骑自行车","facts":[
  {"fact_type":"action","fact_key":"name","fact_value":"骑自行车","confidence":1.0},
  {"fact_type":"person","fact_key":"relation","fact_value":"女儿","confidence":1.0},
  {"fact_type":"location","fact_key":"place","fact_value":"公园","confidence":1.0},
  {"fact_type":"time","fact_key":"date","fact_value":"今天","confidence":1.0},
  {"fact_type":"reference","fact_key":"type","fact_value":"person","confidence":1.0},
  {"fact_type":"reference","fact_key":"value","fact_value":"她","confidence":1.0},
  {"fact_type":"reference","fact_key":"resolved","fact_value":false,"confidence":1.0}
]}

示例2（"去年开始创业，今年赚到第一笔利润，希望明年成立自己的公司"）：
{"summary":"去年创业今年盈利，计划明年成立公司","facts":[
  {"fact_type":"action","fact_key":"name","fact_value":"开始创业","confidence":1.0},
  {"fact_type":"action","fact_key":"name","fact_value":"赚到利润","confidence":1.0},
  {"fact_type":"time","fact_key":"date","fact_value":"去年","confidence":1.0},
  {"fact_type":"time","fact_key":"date","fact_value":"今年","confidence":1.0},
  {"fact_type":"time","fact_key":"date","fact_value":"明年","confidence":1.0},
  {"fact_type":"intent","fact_key":"type","fact_value":"plan","confidence":0.8},
  {"fact_type":"intent","fact_key":"content","fact_value":"成立公司","confidence":0.8}
]}'''; 

const String intentDetectionSystemPrompt = '''
你是一个意图检测器，专门识别用户消息中的特定意图。

需要识别的意图类型：
1. SET_AI_NAME: 用户给AI起名字或改名字
2. SET_USER_NICKNAME: 用户让AI叫他/她什么
3. NONE: 没有上述意图

判断标准：
- SET_AI_NAME: 用户明确表达想要给AI改名的意图，如"你叫XX吧"、"以后你就叫XX"、"给你起个名字叫XX"、"我觉得你叫XX好听"等。注意：疑问句（如"你叫什么？"）不算。
- SET_USER_NICKNAME: 用户明确表达想要让AI改称呼的意图，如"叫我XX"、"以后叫我XX"、"你可以叫我XX"等。注意：疑问句不算。

输出格式（必须是纯JSON）：
{"intent": "SET_AI_NAME"|"SET_USER_NICKNAME"|"NONE", "value": "提取到的名字或称呼，如果没有则为空字符串"}

示例：
输入："以后你就叫幸福无敌吧"
输出：{"intent": "SET_AI_NAME", "value": "幸福无敌"}

输入："叫我小明"
输出：{"intent": "SET_USER_NICKNAME", "value": "小明"}

输入："你好"
输出：{"intent": "NONE", "value": ""}

输入："你叫什么名字？"
输出：{"intent": "NONE", "value": ""}
''';

void loadEnv() {
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('❌ .env 文件不存在');
    exit(1);
  }

  final env = <String, String>{};
  for (final line in envFile.readAsLinesSync()) {
    if (line.contains('=') && !line.startsWith('#')) {
      final idx = line.indexOf('=');
      env[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }
  }

  supabaseUrl = env['SUPABASE_URL'] ?? 'https://vjwolnmswmhpxdsskrmg.supabase.co';
  serviceKey = env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';
  anonKey = env['SUPABASE_ANON_KEY'] ?? '';
  deepseekApiKey = env['DEEPSEEK_API_KEY'] ?? '';

  if (serviceKey.isEmpty) {
    print('❌ 需要在 .env 文件中配置 SUPABASE_SERVICE_ROLE_KEY');
    exit(1);
  }

  print('✅ 配置加载完成');
  print('   Supabase URL: $supabaseUrl');
  print('   Anon Key: ${anonKey.isNotEmpty ? "已配置" : "未配置"}');
  print('   Service Key: ${serviceKey.substring(0, 10)}...');
}

// ============================================
// AI 调用费用计算（单位：元/百万 tokens）
// ============================================

const Map<String, Map<String, double>> aiPricing = {
  // DeepSeek（人民币）
  'deepseek-chat': {'input': 2.0, 'output': 8.0},
  'deepseek-reasoner': {'input': 4.0, 'output': 16.0},
  // OpenAI（换算为人民币，汇率约7.2）
  'gpt-4o-mini': {'input': 1.08, 'output': 4.32},
  'gpt-3.5-turbo': {'input': 3.60, 'output': 10.80},
  'gpt-4o': {'input': 18.0, 'output': 72.0},
};

double calculateCost(String model, int promptTokens, int completionTokens) {
  final price = aiPricing[model];
  if (price == null) return 0.0;
  final inputCost = (promptTokens / 1000000) * (price['input'] ?? 0);
  final outputCost = (completionTokens / 1000000) * (price['output'] ?? 0);
  return inputCost + outputCost;
}

String formatCost(double cost) {
  if (cost < 0.01) return '¥${cost.toStringAsFixed(6)}';
  if (cost < 1) return '¥${cost.toStringAsFixed(4)}';
  return '¥${cost.toStringAsFixed(2)}';
}

Future<void> initDatabase() async {
  try {
    await supabaseSelect('ai_call_logs', select: 'id', limit: 1);
    print('✅ ai_call_logs 表已存在');
  } catch (_) {
    print('⚠️  ai_call_logs 表不存在，AI 调用日志将暂时不记录');
    print('   请在 Supabase SQL Editor 中执行 sql/migrate_007_ai_call_logs.sql');
  }
}

// ============================================
// 用户缓存
// ============================================

Future<void> loadUserCache() async {
  try {
    final users = await supabaseSelect('profiles', select: '*');
    _userCache.clear();
    for (final u in users) {
      final m = u as Map<String, dynamic>;
      if (m['id'] != null) {
        _userCache[m['id'] as String] = m;
      }
    }
    print('✅ 用户缓存已加载: ${_userCache.length} 个用户');
  } catch (e) {
    print('⚠️ 用户缓存加载失败: $e');
  }
}

String getUserName(String? userId) {
  if (userId == null) return '-';
  final user = _userCache[userId];
  if (user == null) return userId.substring(0, 8);
  return user['username'] as String? ?? user['email'] as String? ?? userId.substring(0, 8);
}

// ============================================
// Supabase REST API 辅助函数
// ============================================

Future<List<dynamic>> supabaseSelect(
  String table, {
  String select = '*',
  Map<String, String>? filters,
  String? order,
  bool ascending = false,
  int? limit,
  int? offset,
}) async {
  var path = '/rest/v1/$table?select=$select';

  if (filters != null) {
    for (final entry in filters.entries) {
      path += '&${entry.key}=${entry.value}';
    }
  }
  if (order != null) {
    path += '&order=$order.${ascending ? 'asc' : 'desc'}';
  }
  if (limit != null) {
    path += '&limit=$limit';
  }
  if (offset != null) {
    path += '&offset=$offset';
  }

  final request = await httpClient.getUrl(Uri.parse('$supabaseUrl$path'));
  request.headers.add('apikey', serviceKey);
  request.headers.add('Authorization', 'Bearer $serviceKey');

  final response = await request.close().timeout(
    const Duration(seconds: 15),
    onTimeout: () => throw Exception('Supabase 请求超时: $table'),
  );
  final body = await response.transform(utf8.decoder).join();

  if (response.statusCode != 200) {
    throw Exception('Supabase GET $table 失败: ${response.statusCode} - $body');
  }

  return jsonDecode(body) as List<dynamic>;
}

Future<Map<String, dynamic>> supabaseInsert(String table, Map<String, dynamic> data) async {
  final request = await httpClient.postUrl(Uri.parse('$supabaseUrl/rest/v1/$table'));
  request.headers.add('apikey', serviceKey);
  request.headers.add('Authorization', 'Bearer $serviceKey');
  request.headers.add('Content-Type', 'application/json; charset=utf-8');
  request.headers.add('Prefer', 'return=representation');
  request.add(utf8.encode(jsonEncode(data)));

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  if (response.statusCode != 201) {
    throw Exception('Supabase INSERT $table 失败: ${response.statusCode} - $body');
  }

  final result = jsonDecode(body) as List<dynamic>;
  return result.isNotEmpty ? result.first as Map<String, dynamic> : {};
}

Future<void> supabaseUpdate(String table, Map<String, dynamic> data, String filter) async {
  final request = await httpClient.patchUrl(Uri.parse('$supabaseUrl/rest/v1/$table?$filter'));
  request.headers.add('apikey', serviceKey);
  request.headers.add('Authorization', 'Bearer $serviceKey');
  request.headers.add('Content-Type', 'application/json; charset=utf-8');
  request.headers.add('Prefer', 'return=minimal');
  request.add(utf8.encode(jsonEncode(data)));

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  if (response.statusCode != 204 && response.statusCode != 200) {
    throw Exception('Supabase UPDATE $table 失败: ${response.statusCode} - $body');
  }
}

Future<void> supabaseDelete(String table, String filter) async {
  final request = await httpClient.deleteUrl(Uri.parse('$supabaseUrl/rest/v1/$table?$filter'));
  request.headers.add('apikey', serviceKey);
  request.headers.add('Authorization', 'Bearer $serviceKey');

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  if (response.statusCode != 204 && response.statusCode != 200) {
    throw Exception('Supabase DELETE $table 失败: ${response.statusCode} - $body');
  }
}

// ============================================
// DeepSeek API
// ============================================

class AiCallResult {
  final String content;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  AiCallResult({
    required this.content,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });
}

Future<AiCallResult> callDeepSeekWithUsage(String systemPrompt, String userPrompt, {double temperature = 0.2, String? callType, String? userId, String? extra}) async {
  final startTime = DateTime.now();
  final request = await httpClient.postUrl(Uri.parse('https://api.deepseek.com/v1/chat/completions'));
  request.headers.add('Authorization', 'Bearer $deepseekApiKey');
  request.headers.add('Content-Type', 'application/json; charset=utf-8');

  final body = jsonEncode({
    'model': 'deepseek-chat',
    'messages': [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ],
    'stream': false,
    'temperature': temperature,
    'top_p': 0.3,
    'max_tokens': 1500,
  });
  request.add(utf8.encode(body));

  final response = await request.close();
  final respBody = await response.transform(utf8.decoder).join();
  final latencyMs = DateTime.now().difference(startTime).inMilliseconds;

  if (response.statusCode != 200) {
    if (callType != null) {
      try {
        await supabaseInsert('ai_call_logs', {
          'call_type': callType,
          'model': 'deepseek-chat',
          'provider': 'deepseek',
          'user_id': userId,
          'prompt': userPrompt.length > 500 ? userPrompt.substring(0, 500) : userPrompt,
          'system_prompt_preview': systemPrompt.length > 200 ? systemPrompt.substring(0, 200) : systemPrompt,
          'status': 'failed',
          'error_message': 'HTTP ${response.statusCode}: ${respBody.length > 500 ? respBody.substring(0, 500) : respBody}',
          'latency_ms': latencyMs,
          'extra': extra,
        });
      } catch (_) {}
    }
    throw Exception('DeepSeek API 调用失败: ${response.statusCode} - $respBody');
  }

  final result = jsonDecode(respBody) as Map<String, dynamic>;
  final choices = result['choices'] as List<dynamic>;
  if (choices.isEmpty) {
    if (callType != null) {
      try {
        await supabaseInsert('ai_call_logs', {
          'call_type': callType,
          'model': 'deepseek-chat',
          'provider': 'deepseek',
          'user_id': userId,
          'prompt': userPrompt.length > 500 ? userPrompt.substring(0, 500) : userPrompt,
          'system_prompt_preview': systemPrompt.length > 200 ? systemPrompt.substring(0, 200) : systemPrompt,
          'status': 'failed',
          'error_message': '返回空结果',
          'latency_ms': latencyMs,
          'extra': extra,
        });
      } catch (_) {}
    }
    throw Exception('DeepSeek 返回空结果');
  }

  final content = (choices.first as Map<String, dynamic>)['message']['content'] as String;
  final usage = result['usage'] as Map<String, dynamic>?;
  final promptTokens = (usage?['prompt_tokens'] as num?)?.toInt() ?? 0;
  final completionTokens = (usage?['completion_tokens'] as num?)?.toInt() ?? 0;
  final totalTokens = (usage?['total_tokens'] as num?)?.toInt() ?? 0;

  if (callType != null) {
    try {
      await supabaseInsert('ai_call_logs', {
        'call_type': callType,
        'model': 'deepseek-chat',
        'provider': 'deepseek',
        'user_id': userId,
        'prompt': userPrompt.length > 500 ? userPrompt.substring(0, 500) : userPrompt,
        'system_prompt_preview': systemPrompt.length > 200 ? systemPrompt.substring(0, 200) : systemPrompt,
        'response': content.length > 1000 ? content.substring(0, 1000) : content,
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'total_tokens': totalTokens,
        'status': 'success',
        'latency_ms': latencyMs,
        'temperature': temperature,
        'extra': extra,
      });
    } catch (_) {}
  }

  return AiCallResult(
    content: content,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: totalTokens,
  );
}

Future<String> callDeepSeek(String systemPrompt, String userPrompt, {double temperature = 0.2}) async {
  final result = await callDeepSeekWithUsage(systemPrompt, userPrompt, temperature: temperature);
  return result.content;
}

// ============================================
// 事实提取
// ============================================

Future<Map<String, dynamic>> extractFactsFromMessage(String messageId) async {
  final messages = await supabaseSelect('messages', filters: {'id': 'eq.$messageId'});
  if (messages.isEmpty) throw Exception('消息不存在: $messageId');
  final msg = messages.first as Map<String, dynamic>;
  final userId = msg['user_id'] as String;
  final content = msg['content'] as String;

  final userPrompt = '请从以下用户消息中提取所有客观事实，按 JSON 对象格式输出（包含 summary 和 facts）：\n\n用户消息："""$content"""\n\n请只输出 JSON，不要输出任何其他文字。';
  
  Map<String, dynamic>? bestResult;
  int bestFactCount = -1;
  String bestSummary = '';
  
  for (int attempt = 0; attempt < 3; attempt++) {
    try {
      final aiResult = await callDeepSeekWithUsage(
        factExtractionSystemPrompt,
        userPrompt,
        temperature: 0.1,
        callType: 'fact_extraction',
        userId: userId,
        extra: jsonEncode({'message_id': messageId, 'attempt': attempt}),
      );
      final aiResponse = aiResult.content;
      
      String jsonStr = aiResponse.trim();
      if (jsonStr.startsWith('```json')) jsonStr = jsonStr.substring(7);
      if (jsonStr.startsWith('```')) jsonStr = jsonStr.substring(3);
      if (jsonStr.endsWith('```')) jsonStr = jsonStr.substring(0, jsonStr.length - 3);
      jsonStr = jsonStr.trim();
      
      final jsonObj = jsonDecode(jsonStr) as Map<String, dynamic>;
      final summary = (jsonObj['summary'] as String?)?.trim() ?? '';
      final facts = jsonObj['facts'] as List<dynamic>? ?? [];
      
      if (facts.length > bestFactCount || 
          (facts.length == bestFactCount && summary.isNotEmpty && bestSummary.isEmpty)) {
        bestResult = jsonObj;
        bestFactCount = facts.length;
        bestSummary = summary;
      }
      
      if (facts.length >= 1) break;
    } catch (e) {
      print('提取尝试 $attempt 失败: $e');
      if (attempt == 2 && bestResult == null) rethrow;
    }
  }
  
  if (bestResult == null) {
    bestResult = {'summary': '', 'facts': []};
    bestSummary = '';
    bestFactCount = 0;
  }
  
  final summary = (bestResult['summary'] as String?)?.trim() ?? '';
  final facts = bestResult['facts'] as List<dynamic>? ?? [];

  await supabaseDelete('extracted_facts', 'message_id=eq.$messageId');
  await supabaseDelete('fact_groups', 'message_id=eq.$messageId');

  final groupResult = await supabaseInsert('fact_groups', {
    'message_id': messageId,
    'user_id': userId,
    'summary': summary,
    'fact_count': facts.length,
    'raw_content': jsonEncode(bestResult),
  });
  final groupId = groupResult['id'] as String;

  for (final fact in facts) {
    final f = fact as Map<String, dynamic>;
    await supabaseInsert('extracted_facts', {
      'message_id': messageId,
      'user_id': userId,
      'fact_group_id': groupId,
      'fact_type': f['fact_type'] ?? 'other',
      'fact_key': f['fact_key'] ?? 'content',
      'fact_value': (f['fact_value'] ?? '').toString(),
      'confidence': (f['confidence'] as num?)?.toDouble() ?? 0.0,
      'raw_content': jsonEncode(bestResult),
    });
  }

  await supabaseUpdate('messages', {'extracted': true, 'extraction_error': null}, 'id=eq.$messageId');

  return {'success': true, 'fact_count': facts.length, 'summary': summary, 'group_id': groupId, 'facts': facts};
}

// ============================================
// API 路由处理
// ============================================

Future<void> handleApi(HttpRequest request, String path) async {
  final response = request.response;
  response.headers.contentType = ContentType.json;

  try {
    // 配置接口（前端登录用）
    if (path == '/api/config' && request.method == 'GET') {
      response.write(jsonEncode({
        'supabaseUrl': supabaseUrl,
        'anonKey': anonKey,
      }));
      return;
    }

    // 仪表盘 - 并行查询优化速度
    if (path == '/api/dashboard' && request.method == 'GET') {
      final results = await Future.wait([
        supabaseSelect('profiles', select: 'id'),
        supabaseSelect('messages', select: 'id'),
        supabaseSelect('messages', select: 'id,extracted', filters: {'role': 'eq.user'}),
        supabaseSelect('extracted_facts', select: 'id'),
        supabaseSelect('extracted_facts', select: 'message_id'),
      ]);

      final users = results[0] as List;
      final messages = results[1] as List;
      final allUserMsgs = results[2] as List;
      final facts = results[3] as List;
      final messagesWithFacts = results[4] as List;

      final factMessageIds = messagesWithFacts
          .map((m) => (m as Map<String, dynamic>)['message_id'] as String)
          .toSet();

      final unextracted = allUserMsgs.where((m) {
        final extracted = (m as Map<String, dynamic>)['extracted'] as bool? ?? false;
        return !extracted;
      }).toList();

      int inconsistent = 0;
      for (final msg in unextracted) {
        final msgId = (msg as Map<String, dynamic>)['id'] as String;
        if (factMessageIds.contains(msgId)) inconsistent++;
      }

      int failedLogs = 0;
      try {
        final logs = await supabaseSelect('operation_logs', select: 'id', filters: {'status': 'eq.failed'});
        failedLogs = logs.length;
      } catch (_) {}

      response.write(jsonEncode({
        'users': users.length,
        'messages': messages.length,
        'userMessages': allUserMsgs.length,
        'facts': facts.length,
        'failedLogs': failedLogs,
        'unextracted': unextracted.length,
        'inconsistent': inconsistent,
      }));
      return;
    }

    // 消息列表 - 包含用户名
    if (path == '/api/messages' && request.method == 'GET') {
      final params = request.uri.queryParameters;
      final page = int.tryParse(params['page'] ?? '1') ?? 1;
      final limit = int.tryParse(params['limit'] ?? '20') ?? 20;
      final keyword = params['keyword']?.trim();

      final filters = <String, String>{};
      if (params['role'] != null && params['role']!.isNotEmpty) {
        filters['role'] = 'eq.${params['role']}';
      }

      // 获取全部消息
      final allData = await supabaseSelect('messages',
        select: 'id,user_id,role,content,extracted,extraction_error,created_at',
        filters: filters.isNotEmpty ? filters : null,
        order: 'created_at',
        ascending: false,
      );

      // 按 keyword 搜索（搜索消息内容）
      if (keyword != null && keyword.isNotEmpty) {
        final kw = keyword.toLowerCase();
        allData.retainWhere((m) {
          final content = (m as Map<String, dynamic>)['content'] as String? ?? '';
          return content.toLowerCase().contains(kw);
        });
      }

      // 获取所有事实数据，按 message_id 分组统计
      final allFacts = await supabaseSelect('extracted_facts', select: 'message_id');
      final factCounts = <String, int>{};
      for (final f in allFacts) {
        final mid = (f as Map<String, dynamic>)['message_id'] as String?;
        if (mid != null) {
          factCounts[mid] = (factCounts[mid] ?? 0) + 1;
        }
      }

      // 获取所有已创建的事实组对应的 message_id
      final allGroups = await supabaseSelect('fact_groups', select: 'message_id');
      final existingGroupMessageIds = <String>{};
      for (final g in allGroups) {
        final mid = (g as Map<String, dynamic>)['message_id'] as String?;
        if (mid != null) existingGroupMessageIds.add(mid);
      }

      // 为已提取但没有事实组的消息补建空事实组
      for (final m in allData) {
        final msg = m as Map<String, dynamic>;
        final msgId = msg['id'] as String?;
        final extracted = msg['extracted'] as bool? ?? false;
        if (msgId != null && extracted && !existingGroupMessageIds.contains(msgId)) {
          final userId = msg['user_id'] as String;
          final content = msg['content'] as String;
          await supabaseInsert('fact_groups', {
            'message_id': msgId,
            'user_id': userId,
            'summary': '(未提取到事实)',
            'fact_count': 0,
            'raw_content': '{"summary":"(未提取到事实)","facts":[]}',
          });
          existingGroupMessageIds.add(msgId);
        }
      }

      // 按提取状态过滤
      List<dynamic> filtered = allData;
      if (params['extracted'] == 'true') {
        filtered = allData.where((m) => (m as Map<String, dynamic>)['extracted'] as bool? ?? false).toList();
      } else if (params['extracted'] == 'false') {
        filtered = allData.where((m) => !((m as Map<String, dynamic>)['extracted'] as bool? ?? false)).toList();
      }

      // 代码分页
      final offset = (page - 1) * limit;
      final paged = filtered.skip(offset).take(limit).toList();

      // 添加用户名和事实条数
      final result = paged.map((m) {
        final msg = m as Map<String, dynamic>;
        final msgId = msg['id'] as String?;
        return {
          ...msg,
          'user_name': getUserName(msg['user_id'] as String?),
          'fact_count': msgId != null ? (factCounts[msgId] ?? 0) : 0,
        };
      }).toList();

      response.write(jsonEncode({
        'data': result,
        'page': page,
        'limit': limit,
        'total': filtered.length,
      }));
      return;
    }

    // 事实组列表（按组展示）
    if (path == '/api/fact-groups' && request.method == 'GET') {
      final params = request.uri.queryParameters;
      final page = int.tryParse(params['page'] ?? '1') ?? 1;
      final limit = int.tryParse(params['limit'] ?? '20') ?? 20;
      final keyword = params['keyword']?.trim();
      final factTypeFilter = params['fact_type'];

      var allGroups = await supabaseSelect('fact_groups',
        select: 'id,message_id,user_id,summary,fact_count,created_at',
        order: 'created_at',
        ascending: false,
      );

      // 按 keyword 搜索（搜索摘要）
      if (keyword != null && keyword.isNotEmpty) {
        final kw = keyword.toLowerCase();
        allGroups = allGroups.where((g) {
          final summary = (g as Map<String, dynamic>)['summary'] as String? ?? '';
          return summary.toLowerCase().contains(kw);
        }).toList();
      }

      // 按事实类型过滤
      if (factTypeFilter != null && factTypeFilter.isNotEmpty) {
        final groupsWithType = <String>{};
        final facts = await supabaseSelect('extracted_facts',
          select: 'fact_group_id',
          filters: {'fact_type': 'eq.$factTypeFilter'},
        );
        for (final f in facts) {
          final gid = (f as Map<String, dynamic>)['fact_group_id'] as String?;
          if (gid != null) groupsWithType.add(gid);
        }
        allGroups = allGroups.where((g) {
          final gid = (g as Map<String, dynamic>)['id'] as String;
          return groupsWithType.contains(gid);
        }).toList();
      }

      final offset = (page - 1) * limit;
      final paged = allGroups.skip(offset).take(limit).toList();

      final groupIds = paged
          .map((g) => (g as Map<String, dynamic>)['id'] as String)
          .toList();

      Map<String, List<Map<String, dynamic>>> factsByGroup = {};
      if (groupIds.isNotEmpty) {
        final facts = await supabaseSelect('extracted_facts',
          select: 'id,fact_group_id,fact_type,fact_key,fact_value,confidence',
          filters: {'fact_group_id': 'in.(${groupIds.join(",")})'},
        );
        for (final f in facts) {
          final ff = f as Map<String, dynamic>;
          final gid = ff['fact_group_id'] as String?;
          if (gid != null) {
            factsByGroup.putIfAbsent(gid, () => []).add(ff);
          }
        }
      }

      final messageIds = paged
          .map((g) => (g as Map<String, dynamic>)['message_id'] as String?)
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<String, String> messageMap = {};
      if (messageIds.isNotEmpty) {
        final msgs = await supabaseSelect('messages',
          select: 'id,content',
          filters: {'id': 'in.(${messageIds.join(",")})'},
        );
        for (final m in msgs) {
          final mm = m as Map<String, dynamic>;
          messageMap[mm['id'] as String] = mm['content'] as String? ?? '';
        }
      }

      final result = paged.map((g) {
        final group = g as Map<String, dynamic>;
        final gid = group['id'] as String;
        return {
          ...group,
          'user_name': getUserName(group['user_id'] as String?),
          'message_content': messageMap[group['message_id'] as String?] ?? '',
          'facts': factsByGroup[gid] ?? [],
        };
      }).toList();

      response.write(jsonEncode({
        'data': result,
        'page': page,
        'limit': limit,
        'total': allGroups.length,
      }));
      return;
    }

    // 事实列表 - 包含消息内容和用户名
    if (path == '/api/facts' && request.method == 'GET') {
      final params = request.uri.queryParameters;
      final page = int.tryParse(params['page'] ?? '1') ?? 1;
      final limit = int.tryParse(params['limit'] ?? '20') ?? 20;
      final keyword = params['keyword']?.trim();

      final filters = <String, String>{};
      if (params['fact_type'] != null && params['fact_type']!.isNotEmpty) {
        filters['fact_type'] = 'eq.${params['fact_type']}';
      }

      // 获取全部事实（数据量小，在代码中过滤和分页）
      final allData = await supabaseSelect('extracted_facts',
        select: 'id,message_id,user_id,fact_group_id,fact_type,fact_key,fact_value,confidence,raw_content,created_at',
        filters: filters.isNotEmpty ? filters : null,
        order: 'created_at',
        ascending: false,
      );

      // 按 keyword 搜索（搜索 fact_value 和 fact_key）
      if (keyword != null && keyword.isNotEmpty) {
        final kw = keyword.toLowerCase();
        allData.retainWhere((f) {
          final fact = f as Map<String, dynamic>;
          final key = (fact['fact_key'] as String? ?? '').toLowerCase();
          final value = (fact['fact_value'] as String? ?? '').toLowerCase();
          return key.contains(kw) || value.contains(kw);
        });
      }

      // 代码分页
      final offset = (page - 1) * limit;
      final paged = allData.skip(offset).take(limit).toList();

      // 批量获取相关消息内容
      final messageIds = paged
          .map((f) => (f as Map<String, dynamic>)['message_id'] as String?)
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<String, String> messageMap = {};
      if (messageIds.isNotEmpty) {
        final messages = await supabaseSelect('messages',
          select: 'id,content',
          filters: {'id': 'in.(${messageIds.join(",")})'},
        );
        for (final m in messages) {
          final mm = m as Map<String, dynamic>;
          messageMap[mm['id'] as String] = mm['content'] as String? ?? '';
        }
      }

      // 添加消息内容和用户名
      final result = paged.map((f) {
        final fact = f as Map<String, dynamic>;
        return {
          ...fact,
          'message_content': messageMap[fact['message_id'] as String?] ?? '',
          'user_name': getUserName(fact['user_id'] as String?),
        };
      }).toList();

      response.write(jsonEncode({
        'data': result,
        'page': page,
        'limit': limit,
        'total': allData.length,
      }));
      return;
    }

    // 操作日志
    if (path == '/api/logs' && request.method == 'GET') {
      final params = request.uri.queryParameters;
      final page = int.tryParse(params['page'] ?? '1') ?? 1;
      final limit = int.tryParse(params['limit'] ?? '20') ?? 20;
      final keyword = params['keyword']?.trim();

      List<dynamic> data = [];
      try {
        data = await supabaseSelect('operation_logs',
          select: '*',
          order: 'created_at',
          ascending: false,
        );

        // 按 keyword 搜索（搜索 description 和 details）
        if (keyword != null && keyword.isNotEmpty) {
          final kw = keyword.toLowerCase();
          data = data.where((l) {
            final log = l as Map<String, dynamic>;
            final desc = (log['description'] as String? ?? '').toLowerCase();
            final details = (log['details'] as String? ?? '').toLowerCase();
            return desc.contains(kw) || details.contains(kw);
          }).toList();
        }

        if (params['status'] != null && params['status']!.isNotEmpty) {
          data = data.where((l) => (l as Map<String, dynamic>)['status'] == params['status']).toList();
        }

        if (params['operation_type'] != null && params['operation_type']!.isNotEmpty) {
          data = data.where((l) => (l as Map<String, dynamic>)['operation_type'] == params['operation_type']).toList();
        }

        if (params['category'] != null && params['category']!.isNotEmpty) {
          final category = params['category']!;
          final typeMap = {
            'message': ['message_send', 'message_save', 'message_load'],
            'ai': ['ai_response', 'ai_error'],
            'fact': ['fact_extract', 'fact_extract_success', 'fact_extract_failure'],
            'auth': ['auth_login', 'auth_login_success', 'auth_login_failure', 'auth_register', 'auth_register_success', 'auth_register_failure', 'auth_logout'],
            'user': ['profile_update', 'profile_update_success', 'profile_update_failure'],
            'system': ['system_startup', 'system_error'],
          };
          final types = typeMap[category] ?? [];
          if (types.isNotEmpty) {
            data = data.where((l) => types.contains((l as Map<String, dynamic>)['operation_type'])).toList();
          }
        }

        final total = data.length;

        final offset = (page - 1) * limit;
        data = data.skip(offset).take(limit).toList();

        data = data.map((l) {
          final log = l as Map<String, dynamic>;
          final opType = log['operation_type'] as String? ?? '';
          String cat = '其他';
          if (['message_send', 'message_save', 'message_load'].contains(opType)) cat = '消息';
          else if (['ai_response', 'ai_error'].contains(opType)) cat = 'AI';
          else if (opType.startsWith('fact_extract')) cat = '事实提取';
          else if (opType.startsWith('auth_login') || opType.startsWith('auth_register') || opType == 'auth_logout') cat = '认证';
          else if (opType.startsWith('profile_update')) cat = '用户';
          else if (opType.startsWith('system')) cat = '系统';
          else if (opType.startsWith('database')) cat = '数据库';
          else if (opType.startsWith('http')) cat = '网络';
          else if (opType.startsWith('memory') || opType.startsWith('daily_log')) cat = '业务';

          final displayNames = {
            'message_send': '发送消息', 'message_save': '保存消息', 'message_load': '加载消息',
            'ai_response': 'AI响应', 'ai_error': 'AI错误',
            'fact_extract': '事实提取', 'fact_extract_success': '提取成功', 'fact_extract_failure': '提取失败',
            'auth_login': '登录', 'auth_login_success': '登录成功', 'auth_login_failure': '登录失败',
            'auth_register': '注册', 'auth_register_success': '注册成功', 'auth_register_failure': '注册失败',
            'auth_logout': '登出',
            'profile_update': '更新资料', 'profile_update_success': '更新成功', 'profile_update_failure': '更新失败',
            'system_startup': '系统启动', 'system_error': '系统错误',
            'database_query': '数据库查询', 'database_insert': '数据库插入', 'database_update': '数据库更新', 'database_delete': '数据库删除',
            'http_request': 'HTTP请求', 'http_response': 'HTTP响应', 'http_error': 'HTTP错误',
            'memory_create': '创建记忆', 'memory_update': '更新记忆', 'memory_delete': '删除记忆',
            'daily_log_create': '创建日志', 'daily_log_update': '更新日志',
          };

          return {
            ...log,
            'user_name': getUserName(log['user_id'] as String?),
            'category': cat,
            'operation_type_display': displayNames[opType] ?? opType,
          };
        }).toList();
      } catch (e) {
        // operation_logs 表可能不存在
      }

      response.write(jsonEncode({'data': data, 'page': page, 'limit': limit, 'total': data.length}));
      return;
    }

    // 日志统计
    if (path == '/api/logs/statistics' && request.method == 'GET') {
      final stats = {
        'message': 0, 'ai': 0, 'fact': 0, 'auth': 0, 'user': 0, 'system': 0, 'database': 0, 'http': 0, 'business': 0, 'other': 0,
        'success': 0, 'failed': 0, 'pending': 0, 'info': 0,
        'total': 0,
      };

      try {
        final data = await supabaseSelect('operation_logs', select: 'operation_type,status');
        stats['total'] = data.length;

        for (final log in data) {
          final l = log as Map<String, dynamic>;
          final opType = l['operation_type'] as String? ?? '';
          final status = l['status'] as String? ?? '';

          stats[status] = (stats[status] as int) + 1;

          if (['message_send', 'message_save', 'message_load'].contains(opType)) stats['message'] = (stats['message'] as int) + 1;
          else if (['ai_response', 'ai_error'].contains(opType)) stats['ai'] = (stats['ai'] as int) + 1;
          else if (opType.startsWith('fact_extract')) stats['fact'] = (stats['fact'] as int) + 1;
          else if (opType.startsWith('auth_login') || opType.startsWith('auth_register') || opType == 'auth_logout') stats['auth'] = (stats['auth'] as int) + 1;
          else if (opType.startsWith('profile_update')) stats['user'] = (stats['user'] as int) + 1;
          else if (opType.startsWith('system')) stats['system'] = (stats['system'] as int) + 1;
          else if (opType.startsWith('database')) stats['database'] = (stats['database'] as int) + 1;
          else if (opType.startsWith('http')) stats['http'] = (stats['http'] as int) + 1;
          else if (opType.startsWith('memory') || opType.startsWith('daily_log')) stats['business'] = (stats['business'] as int) + 1;
          else stats['other'] = (stats['other'] as int) + 1;
        }
      } catch (e) {
        // operation_logs 表可能不存在
      }

      response.write(jsonEncode(stats));
      return;
    }

    // AI 调用日志列表
    if (path == '/api/ai-logs' && request.method == 'GET') {
      final params = request.uri.queryParameters;
      final page = int.tryParse(params['page'] ?? '1') ?? 1;
      final limit = int.tryParse(params['limit'] ?? '20') ?? 20;
      final keyword = params['keyword']?.trim();

      List<dynamic> data = [];
      try {
        data = await supabaseSelect('ai_call_logs',
          select: '*',
          order: 'created_at',
          ascending: false,
        );

        if (keyword != null && keyword.isNotEmpty) {
          final kw = keyword.toLowerCase();
          data = data.where((l) {
            final log = l as Map<String, dynamic>;
            final callType = (log['call_type'] as String? ?? '').toLowerCase();
            final prompt = (log['prompt'] as String? ?? '').toLowerCase();
            final response = (log['response'] as String? ?? '').toLowerCase();
            return callType.contains(kw) || prompt.contains(kw) || response.contains(kw);
          }).toList();
        }

        if (params['call_type'] != null && params['call_type']!.isNotEmpty) {
          data = data.where((l) => (l as Map<String, dynamic>)['call_type'] == params['call_type']).toList();
        }

        if (params['status'] != null && params['status']!.isNotEmpty) {
          data = data.where((l) => (l as Map<String, dynamic>)['status'] == params['status']).toList();
        }

        final total = data.length;
        final offset = (page - 1) * limit;
        data = data.skip(offset).take(limit).toList();

        data = data.map((l) {
          final log = l as Map<String, dynamic>;
          final model = log['model'] as String? ?? '';
          final promptTokens = (log['prompt_tokens'] as num?)?.toInt() ?? 0;
          final completionTokens = (log['completion_tokens'] as num?)?.toInt() ?? 0;
          final cost = calculateCost(model, promptTokens, completionTokens);
          final price = aiPricing[model];
          return {
            ...log,
            'user_name': getUserName(log['user_id'] as String?),
            'cost': cost,
            'cost_display': formatCost(cost),
            'input_price': price?['input'] ?? 0,
            'output_price': price?['output'] ?? 0,
          };
        }).toList();

        response.write(jsonEncode({'data': data, 'page': page, 'limit': limit, 'total': total}));
      } catch (e) {
        response.write(jsonEncode({'data': [], 'page': page, 'limit': limit, 'total': 0, 'error': e.toString()}));
      }
      return;
    }

    // AI 调用日志统计
    if (path == '/api/ai-logs/statistics' && request.method == 'GET') {
      final stats = <String, dynamic>{
        'total': 0,
        'success': 0,
        'failed': 0,
        'total_tokens': 0,
        'prompt_tokens': 0,
        'completion_tokens': 0,
        'total_latency_ms': 0,
        'total_cost': 0.0,
        'fact_extraction': 0,
        'intent_detection': 0,
        'chat': 0,
        'other': 0,
      };

      try {
        final data = await supabaseSelect('ai_call_logs', select: 'call_type,status,prompt_tokens,completion_tokens,total_tokens,latency_ms,model');
        stats['total'] = data.length;

        for (final log in data) {
          final l = log as Map<String, dynamic>;
          final status = l['status'] as String? ?? '';
          final callType = l['call_type'] as String? ?? '';
          final model = l['model'] as String? ?? '';
          final promptTokens = (l['prompt_tokens'] as num?)?.toInt() ?? 0;
          final completionTokens = (l['completion_tokens'] as num?)?.toInt() ?? 0;

          if (status == 'success') stats['success'] = (stats['success'] as int) + 1;
          else if (status == 'failed') stats['failed'] = (stats['failed'] as int) + 1;

          stats['prompt_tokens'] = (stats['prompt_tokens'] as int) + promptTokens;
          stats['completion_tokens'] = (stats['completion_tokens'] as int) + completionTokens;
          stats['total_tokens'] = (stats['total_tokens'] as int) + ((l['total_tokens'] as num?)?.toInt() ?? 0);
          stats['total_latency_ms'] = (stats['total_latency_ms'] as int) + ((l['latency_ms'] as num?)?.toInt() ?? 0);
          stats['total_cost'] = (stats['total_cost'] as double) + calculateCost(model, promptTokens, completionTokens);

          if (callType == 'fact_extraction') stats['fact_extraction'] = (stats['fact_extraction'] as int) + 1;
          else if (callType == 'intent_detection') stats['intent_detection'] = (stats['intent_detection'] as int) + 1;
          else if (callType == 'chat') stats['chat'] = (stats['chat'] as int) + 1;
          else stats['other'] = (stats['other'] as int) + 1;
        }

        final totalLatency = stats['total_latency_ms'] as int;
        final totalCount = stats['total'] as int;
        stats['avg_latency_ms'] = totalCount > 0 ? (totalLatency / totalCount).round() : 0;
        stats['total_cost_display'] = formatCost(stats['total_cost'] as double);
        stats['avg_cost'] = totalCount > 0 ? (stats['total_cost'] as double) / totalCount : 0.0;
        stats['avg_cost_display'] = formatCost(stats['avg_cost'] as double);
      } catch (e) {
        // ai_call_logs 表可能不存在
      }

      response.write(jsonEncode(stats));
      return;
    }

    // 用户列表
    if (path == '/api/users' && request.method == 'GET') {
      final params = request.uri.queryParameters;
      final page = int.tryParse(params['page'] ?? '1') ?? 1;
      final limit = int.tryParse(params['limit'] ?? '20') ?? 20;
      final keyword = params['keyword']?.trim();

      var data = await supabaseSelect('profiles', select: '*', order: 'created_at', ascending: false);

      // 按 keyword 搜索（搜索用户名、昵称、邮箱）
      if (keyword != null && keyword.isNotEmpty) {
        final kw = keyword.toLowerCase();
        data = data.where((u) {
          final user = u as Map<String, dynamic>;
          final username = (user['username'] as String? ?? '').toLowerCase();
          final nickname = (user['nickname'] as String? ?? '').toLowerCase();
          final email = (user['email'] as String? ?? '').toLowerCase();
          return username.contains(kw) || nickname.contains(kw) || email.contains(kw);
        }).toList();
      }

      // 分页
      final total = data.length;
      final offset = (page - 1) * limit;
      data = data.skip(offset).take(limit).toList();

      response.write(jsonEncode({'data': data, 'page': page, 'limit': limit, 'total': total}));
      return;
    }

    // 刷新用户缓存
    if (path == '/api/users/refresh' && request.method == 'POST') {
      await loadUserCache();
      response.write(jsonEncode({'success': true, 'count': _userCache.length}));
      return;
    }

    // 意图检测 API
    if (path == '/api/detect-intent' && request.method == 'POST') {
      try {
        final body = await utf8.decodeStream(request);
        final jsonBody = jsonDecode(body) as Map<String, dynamic>;
        final message = jsonBody['message'] as String? ?? '';

        if (message.isEmpty) {
          response.write(jsonEncode({'intent': 'NONE', 'value': ''}));
          return;
        }

        final aiResult = await callDeepSeekWithUsage(
          intentDetectionSystemPrompt,
          message,
          temperature: 0.0,
          callType: 'intent_detection',
        );
        final result = aiResult.content;
        
        String jsonStr = result.trim();
        if (jsonStr.startsWith('```json')) jsonStr = jsonStr.substring(7);
        if (jsonStr.startsWith('```')) jsonStr = jsonStr.substring(3);
        if (jsonStr.endsWith('```')) jsonStr = jsonStr.substring(0, jsonStr.length - 3);
        jsonStr = jsonStr.trim();

        final jsonObj = jsonDecode(jsonStr) as Map<String, dynamic>;
        final intent = (jsonObj['intent'] as String?)?.trim() ?? 'NONE';
        final value = (jsonObj['value'] as String?)?.trim() ?? '';

        response.write(jsonEncode({'intent': intent, 'value': value}));
      } catch (e) {
        response.statusCode = 500;
        response.write(jsonEncode({'error': e.toString(), 'intent': 'NONE', 'value': ''}));
      }
      return;
    }

    // 数据检查
    if (path == '/api/check' && request.method == 'GET') {
      final userMessages = await supabaseSelect('messages', select: 'id,content,extracted', filters: {'role': 'eq.user'});
      final allFacts = await supabaseSelect('extracted_facts', select: 'id,message_id');
      final factMessageIds = allFacts.map((m) => (m as Map<String, dynamic>)['message_id'] as String).toSet();

      final issues = <Map<String, dynamic>>[];
      for (final msg in userMessages) {
        final m = msg as Map<String, dynamic>;
        final msgId = m['id'] as String;
        final extracted = m['extracted'] as bool? ?? false;
        final hasFacts = factMessageIds.contains(msgId);

        if (hasFacts && !extracted) {
          final content = m['content'] as String? ?? '';
          issues.add({
            'type': 'inconsistent',
            'message_id': msgId,
            'content': content.length > 50 ? content.substring(0, 50) : content,
            'issue': '已有事实数据但 extracted=false',
          });
        }
      }

      response.write(jsonEncode({
        'totalMessages': userMessages.length,
        'totalFacts': allFacts.length,
        'issues': issues,
        'issueCount': issues.length,
      }));
      return;
    }

    // 修复数据
    if (path == '/api/fix' && request.method == 'POST') {
      final body = await utf8.decoder.bind(request).join();
      final params = jsonDecode(body) as Map<String, dynamic>;
      final action = params['action'] as String?;

      if (action == 'fix_extracted') {
        final userMessages = await supabaseSelect('messages', select: 'id', filters: {'role': 'eq.user', 'extracted': 'neq.true'});
        final allFacts = await supabaseSelect('extracted_facts', select: 'message_id');
        final factMessageIds = allFacts.map((m) => (m as Map<String, dynamic>)['message_id'] as String).toSet();

        int fixed = 0;
        for (final msg in userMessages) {
          final msgId = (msg as Map<String, dynamic>)['id'] as String;
          if (factMessageIds.contains(msgId)) {
            await supabaseUpdate('messages', {'extracted': true, 'extraction_error': null}, 'id=eq.$msgId');
            fixed++;
          }
        }

        response.write(jsonEncode({'fixed': fixed}));
        return;
      }

      response.statusCode = 400;
      response.write(jsonEncode({'error': '未知的修复操作'}));
      return;
    }

    // 手动重新提取
    if (path == '/api/reextract' && request.method == 'POST') {
      if (deepseekApiKey.isEmpty) {
        response.statusCode = 400;
        response.write(jsonEncode({'error': 'DEEPSEEK_API_KEY 未配置'}));
        return;
      }

      final body = await utf8.decoder.bind(request).join();
      final params = jsonDecode(body) as Map<String, dynamic>;
      final messageId = params['message_id'] as String?;

      if (messageId == null) {
        response.statusCode = 400;
        response.write(jsonEncode({'error': '缺少 message_id'}));
        return;
      }

      final result = await extractFactsFromMessage(messageId);
      response.write(jsonEncode(result));
      return;
    }

    // 删除事实
    if (path.startsWith('/api/facts/') && request.method == 'DELETE') {
      final factId = path.split('/').last;
      await supabaseDelete('extracted_facts', 'id=eq.$factId');
      response.write(jsonEncode({'success': true}));
      return;
    }

    // 批量重新提取所有未提取的消息
    if (path == '/api/reextract/all' && request.method == 'POST') {
      if (deepseekApiKey.isEmpty) {
        response.statusCode = 400;
        response.write(jsonEncode({'error': 'DEEPSEEK_API_KEY 未配置'}));
        return;
      }

      final unextracted = await supabaseSelect('messages',
        select: 'id',
        filters: {'role': 'eq.user', 'extracted': 'eq.false'},
      );

      if (unextracted.isEmpty) {
        response.write(jsonEncode({'success': true, 'count': 0, 'success_count': 0, 'failed_count': 0, 'failed_messages': []}));
        return;
      }

      int successCount = 0;
      int failedCount = 0;
      final failedMessages = <String>[];

      for (final msg in unextracted) {
        final msgId = (msg as Map<String, dynamic>)['id'] as String;
        try {
          await extractFactsFromMessage(msgId);
          successCount++;
          print('✅ 消息 $msgId 提取成功');
        } catch (e) {
          failedCount++;
          failedMessages.add('$msgId: $e');
          print('❌ 消息 $msgId 提取失败: $e');
        }
      }

      response.write(jsonEncode({
        'success': true,
        'count': unextracted.length,
        'success_count': successCount,
        'failed_count': failedCount,
        'failed_messages': failedMessages,
      }));
      return;
    }

    response.statusCode = 404;
    response.write(jsonEncode({'error': '未知的 API 路径: $path'}));
  } catch (e) {
    response.statusCode = 500;
    response.write(jsonEncode({'error': e.toString()}));
    print('❌ API 错误 [$path]: $e');
  } finally {
    await response.close();
  }
}

// ============================================
// 静态文件服务
// ============================================

final _mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
};

Future<void> serveStaticFile(HttpRequest request, String path) async {
  final filePath = 'admin/${path.substring('/admin/'.length)}';
  final file = File(filePath);

  if (!file.existsSync()) {
    request.response.statusCode = 404;
    request.response.write('File not found: $filePath');
    await request.response.close();
    return;
  }

  final ext = filePath.substring(filePath.lastIndexOf('.'));
  final contentType = _mimeTypes[ext] ?? 'application/octet-stream';
  request.response.headers.contentType = ContentType.parse(contentType);
  await file.openRead().pipe(request.response);
}

// ============================================
// 主函数
// ============================================

void main() async {
  loadEnv();
  await initDatabase();
  await loadUserCache();

  final server = await HttpServer.bind('0.0.0.0', 8081);
  print('🚀 AI Life 后台管理系统已启动');
  print('   本机访问: http://127.0.0.1:8081');
  print('');

  await for (final request in server) {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      continue;
    }

    final path = request.uri.path;

    try {
      if (path.startsWith('/api/')) {
        await handleApi(request, path);
      } else if (path == '/' || path == '/admin' || path == '/admin/') {
        final file = File('admin/index.html');
        if (file.existsSync()) {
          request.response.headers.contentType = ContentType.html;
          await file.openRead().pipe(request.response);
        } else {
          request.response.statusCode = 404;
          request.response.write('admin/index.html not found');
          await request.response.close();
        }
      } else if (path.startsWith('/admin/')) {
        await serveStaticFile(request, path);
      } else {
        request.response.statusCode = 302;
        request.response.headers.add('Location', '/admin/');
        await request.response.close();
      }
    } catch (e) {
      print('❌ 请求处理错误: $e');
      request.response.statusCode = 500;
      request.response.write('Internal Server Error: $e');
      await request.response.close();
    }
  }
}
