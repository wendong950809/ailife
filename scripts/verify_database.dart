import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
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

  final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);

  print('=== 验证数据库表 ===\n');
  
  final tables = [
    'profiles',
    'memories',
    'memory_embeddings',
    'daily_logs',
    'conversations',
    'messages',
  ];
  
  bool allOk = true;
  
  for (final table in tables) {
    try {
      final result = await supabase.from(table).select('count').limit(1);
      print('✅ $table 表：存在');
    } catch (e) {
      print('❌ $table 表：不存在或无法访问');
      print('   错误: $e');
      allOk = false;
    }
  }
  
  print('\n=== 结论 ===');
  if (allOk) {
    print('✅ 所有表都已成功创建！');
    print('现在可以进行下一步：启用 Email 认证，然后测试注册登录。');
  } else {
    print('❌ 部分表创建失败，请检查 SQL 执行是否有报错。');
  }
  
  exit(0);
}
