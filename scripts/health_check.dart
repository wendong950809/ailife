import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  print('          数据库健康检查');
  print('========================================\n');

  final results = <CheckResult>[];

  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    final supabase = Supabase.instance.client;

    results.addAll(await checkConnection(supabase));
    results.addAll(await checkTables(supabase));
    results.addAll(await checkRlspolicies(supabase));
    results.addAll(await checkDataConsistency(supabase));
    results.addAll(await checkOperationLogs(supabase));

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

Future<List<CheckResult>> checkConnection(SupabaseClient supabase) async {
  final results = <CheckResult>[];
  try {
    await supabase.from('profiles').select('id').limit(1);
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

Future<List<CheckResult>> checkTables(SupabaseClient supabase) async {
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
    try {
      await supabase.from(table).select('id').limit(1);
      results.add(CheckResult(
        name: '表: $table',
        status: CheckStatus.success,
        message: '表存在且可访问',
      ));
    } catch (e) {
      results.add(CheckResult(
        name: '表: $table',
        status: CheckStatus.error,
        message: '表不存在或不可访问: $e',
      ));
    }
  }

  final messagesColumns = await _checkColumns(supabase, 'messages', [
    'id',
    'conversation_id',
    'user_id',
    'role',
    'content',
    'tokens',
    'extracted',
    'extraction_error',
    'created_at',
  ]);
  results.addAll(messagesColumns);

  final profilesColumns = await _checkColumns(supabase, 'profiles', [
    'id',
    'username',
    'bio',
    'avatar_url',
    'birthday',
    'created_at',
    'updated_at',
  ]);
  results.addAll(profilesColumns);

  final extractedFactsColumns = await _checkColumns(supabase, 'extracted_facts', [
    'id',
    'message_id',
    'user_id',
    'fact_type',
    'fact_key',
    'fact_value',
    'confidence',
    'raw_content',
    'created_at',
    'updated_at',
  ]);
  results.addAll(extractedFactsColumns);

  return results;
}

Future<List<CheckResult>> _checkColumns(
    SupabaseClient supabase, String table, List<String> requiredColumns) async {
  final results = <CheckResult>[];
  try {
    final response = await supabase.rpc('list_columns', params: {'table_name': table});
    final existingColumns = (response as List).map((c) => c['name'] as String).toSet();

    final missingColumns = requiredColumns.where((c) => !existingColumns.contains(c)).toList();

    if (missingColumns.isEmpty) {
      results.add(CheckResult(
        name: '字段: $table',
        status: CheckStatus.success,
        message: '所有必需字段都存在',
      ));
    } else {
      results.add(CheckResult(
        name: '字段: $table',
        status: CheckStatus.error,
        message: '缺少字段: ${missingColumns.join(', ')}',
      ));
    }
  } catch (e) {
    results.add(CheckResult(
      name: '字段: $table',
      status: CheckStatus.warning,
      message: '无法检查字段: $e',
    ));
  }
  return results;
}

Future<List<CheckResult>> checkRlspolicies(SupabaseClient supabase) async {
  final results = <CheckResult>[];
  final policies = [
    {'table': 'messages', 'policy': '用户可以更新自己的消息'},
    {'table': 'extracted_facts', 'policy': '用户可以更新自己的事实'},
    {'table': 'profiles', 'policy': '用户可以更新自己的资料'},
  ];

  for (final policy in policies) {
    try {
      final result = await supabase.rpc('check_policy_exists', params: {
        'table_name': policy['table'],
        'policy_name': policy['policy'],
      });
      if (result == true) {
        results.add(CheckResult(
          name: 'RLS策略: ${policy['policy']}',
          status: CheckStatus.success,
          message: '策略存在',
        ));
      } else {
        results.add(CheckResult(
          name: 'RLS策略: ${policy['policy']}',
          status: CheckStatus.warning,
          message: '策略可能不存在',
        ));
      }
    } catch (e) {
      results.add(CheckResult(
        name: 'RLS策略: ${policy['policy']}',
        status: CheckStatus.warning,
        message: '无法检查: $e',
      ));
    }
  }

  return results;
}

Future<List<CheckResult>> checkDataConsistency(SupabaseClient supabase) async {
  final results = <CheckResult>[];

  try {
    final messagesResponse = await supabase
        .from('messages')
        .select('count', count: CountOption.exact)
        .eq('role', 'user');
    final userMessageCount = messagesResponse[0]['count'] as int? ?? 0;

    final extractedFactsResponse = await supabase
        .from('extracted_facts')
        .select('count', count: CountOption.exact);
    final factsCount = extractedFactsResponse[0]['count'] as int? ?? 0;

    final unextractedResponse = await supabase
        .from('messages')
        .select('count', count: CountOption.exact)
        .eq('role', 'user')
        .neq('extracted', true);
    final unextractedCount = unextractedResponse[0]['count'] as int? ?? 0;

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

    if (unextractedCount > 0) {
      results.add(CheckResult(
        name: '未提取消息',
        status: CheckStatus.warning,
        message: '有 $unextractedCount 条消息未标记为已提取',
      ));
    } else {
      results.add(CheckResult(
        name: '未提取消息',
        status: CheckStatus.success,
        message: '所有消息都已标记',
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

Future<List<CheckResult>> checkOperationLogs(SupabaseClient supabase) async {
  final results = <CheckResult>[];

  try {
    final failedCountResponse = await supabase
        .from('operation_logs')
        .select('count', count: CountOption.exact)
        .eq('status', 'failed');
    final failedCount = failedCountResponse[0]['count'] as int? ?? 0;

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