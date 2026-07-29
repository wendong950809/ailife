import 'dart:io';
import 'dart:convert';

enum CheckStatus {
  success,
  warning,
  error,
}

class CheckResult {
  final String name;
  final CheckStatus status;
  final String? message;
  final dynamic data;

  CheckResult({
    required this.name,
    required this.status,
    this.message,
    this.data,
  });

  void printResult() {
    final icon = status == CheckStatus.success
        ? '✅'
        : status == CheckStatus.warning
            ? '⚠️'
            : '❌';
    print('$icon $name');
    if (message != null) {
      print('   $message');
    }
    if (data != null) {
      print('   数据: $data');
    }
  }
}

Future<void> main() async {
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('❌ .env 文件不存在，请先创建配置文件');
    exit(1);
  }

  final env = <String, String>{};
  for (final line in envFile.readAsLinesSync()) {
    if (line.contains('=') && !line.startsWith('#')) {
      final idx = line.indexOf('=');
      env[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }
  }

  final supabaseUrl = env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = env['SUPABASE_ANON_KEY'] ?? '';

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    print('❌ 请在 .env 文件中配置 SUPABASE_URL 和 SUPABASE_ANON_KEY');
    exit(1);
  }

  print('========================================');
  print('          AI Life 数据库健康检查');
  print('========================================\n');

  final results = <CheckResult>[];

  try {
    results.addAll(await checkConnection(supabaseUrl, supabaseAnonKey));
    results.addAll(await checkTables(supabaseUrl, supabaseAnonKey));
    results.addAll(await checkDataConsistency(supabaseUrl, supabaseAnonKey));
    results.addAll(await checkOperationLogs(supabaseUrl, supabaseAnonKey));

  } catch (e) {
    results.add(CheckResult(
      name: '初始化失败',
      status: CheckStatus.error,
      message: '$e',
    ));
  }

  print('\n========================================');
  print('          检查结果汇总');
  print('========================================');

  final successCount = results.where((r) => r.status == CheckStatus.success).length;
  final warningCount = results.where((r) => r.status == CheckStatus.warning).length;
  final errorCount = results.where((r) => r.status == CheckStatus.error).length;

  for (final result in results) {
    result.printResult();
  }

  print('\n📊 统计: $successCount 成功, $warningCount 警告, $errorCount 错误');

  if (errorCount > 0) {
    exit(1);
  } else if (warningCount > 0) {
    exit(2);
  } else {
    exit(0);
  }
}

Future<Map<String, dynamic>> _supabaseGet(String supabaseUrl, String supabaseAnonKey, String path, {Map<String, String>? query}) async {
  final uri = Uri.parse('$supabaseUrl/rest/v1$path');
  final finalUri = query != null ? uri.replace(queryParameters: query) : uri;
  
  final client = HttpClient();
  final request = await client.getUrl(finalUri);
  request.headers.add('apikey', supabaseAnonKey);
  request.headers.add('Authorization', 'Bearer $supabaseAnonKey');
  request.headers.add('Content-Type', 'application/json');
  
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  
  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}: $body');
  }
  
  client.close();
  return {'status': response.statusCode, 'body': jsonDecode(body)};
}

Future<CheckResult> _checkTableExists(String supabaseUrl, String supabaseAnonKey, String tableName) async {
  try {
    await _supabaseGet(supabaseUrl, supabaseAnonKey, '/$tableName?select=id&limit=1');
    return CheckResult(
      name: '表: $tableName',
      status: CheckStatus.success,
      message: '表存在且可访问',
    );
  } catch (e) {
    if (tableName == 'operation_logs') {
      return CheckResult(
        name: '表: $tableName',
        status: CheckStatus.warning,
        message: '表尚未创建（需要执行迁移脚本或在 Supabase 控制台手动创建）',
      );
    }
    return CheckResult(
      name: '表: $tableName',
      status: CheckStatus.error,
      message: '表不存在或不可访问: $e',
    );
  }
}

Future<List<CheckResult>> checkConnection(String supabaseUrl, String supabaseAnonKey) async {
  final results = <CheckResult>[];
  try {
    await _supabaseGet(supabaseUrl, supabaseAnonKey, '/profiles?select=id&limit=1');
    results.add(CheckResult(
      name: '数据库连接',
      status: CheckStatus.success,
      message: '连接正常',
    ));
  } catch (e) {
    results.add(CheckResult(
      name: '数据库连接',
      status: CheckStatus.error,
      message: '连接失败: $e',
    ));
  }
  return results;
}

Future<List<CheckResult>> checkTables(String supabaseUrl, String supabaseAnonKey) async {
  final results = <CheckResult>[];
  final requiredTables = [
    'profiles',
    'messages',
    'extracted_facts',
    'memories',
    'conversations',
    'operation_logs',
  ];

  for (final table in requiredTables) {
    results.add(await _checkTableExists(supabaseUrl, supabaseAnonKey, table));
  }

  return results;
}

Future<List<CheckResult>> checkDataConsistency(String supabaseUrl, String supabaseAnonKey) async {
  final results = <CheckResult>[];

  try {
    final userMessages = await _supabaseGet(supabaseUrl, supabaseAnonKey, '/messages?select=id&role=eq.user');
    final userMessageCount = (userMessages['body'] as List).length;

    final facts = await _supabaseGet(supabaseUrl, supabaseAnonKey, '/extracted_facts?select=id');
    final factsCount = (facts['body'] as List).length;

    final unextracted = await _supabaseGet(supabaseUrl, supabaseAnonKey, '/messages?select=id&role=eq.user&extracted=neq.true');
    final unextractedCount = (unextracted['body'] as List).length;

    final messagesWithFacts = await _supabaseGet(supabaseUrl, supabaseAnonKey, '/extracted_facts?select=message_id');
    final messageIdsWithFacts = (messagesWithFacts['body'] as List)
        .map((m) => m['message_id'] as String)
        .toSet();

    int inconsistentCount = 0;
    if (messageIdsWithFacts.isNotEmpty) {
      for (final msg in unextracted['body'] as List) {
        final msgId = msg['id'] as String;
        if (messageIdsWithFacts.contains(msgId)) {
          inconsistentCount++;
        }
      }
    }

    results.add(CheckResult(
      name: '用户消息数量',
      status: CheckStatus.success,
      data: '$userMessageCount 条',
    ));

    results.add(CheckResult(
      name: '已提取事实数量',
      status: CheckStatus.success,
      data: '$factsCount 条',
    ));

    if (inconsistentCount > 0) {
      results.add(CheckResult(
        name: '数据一致性',
        status: CheckStatus.error,
        message: '发现 $inconsistentCount 条消息已有事实但 extracted=false',
      ));
    } else if (unextractedCount > 0) {
      results.add(CheckResult(
        name: '数据一致性',
        status: CheckStatus.warning,
        message: '有 $unextractedCount 条消息未标记为已提取（可能尚未处理）',
      ));
    } else {
      results.add(CheckResult(
        name: '数据一致性',
        status: CheckStatus.success,
        message: '所有消息提取状态一致',
      ));
    }

  } catch (e) {
    results.add(CheckResult(
      name: '数据一致性检查',
      status: CheckStatus.error,
      message: '检查失败: $e',
    ));
  }

  return results;
}

Future<List<CheckResult>> checkOperationLogs(String supabaseUrl, String supabaseAnonKey) async {
  final results = <CheckResult>[];

  try {
    final failedLogs = await _supabaseGet(supabaseUrl, supabaseAnonKey, '/operation_logs?select=id&status=eq.failed');
    final failedCount = (failedLogs['body'] as List).length;

    if (failedCount > 0) {
      results.add(CheckResult(
        name: '失败操作日志',
        status: CheckStatus.warning,
        message: '有 $failedCount 条失败记录',
      ));
    } else {
      results.add(CheckResult(
        name: '失败操作日志',
        status: CheckStatus.success,
        message: '没有失败记录',
      ));
    }

  } catch (e) {
    results.add(CheckResult(
      name: '操作日志检查',
      status: CheckStatus.warning,
      message: '无法检查: $e',
    ));
  }

  return results;
}