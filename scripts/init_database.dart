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

  print('=== 检查 Supabase 连接 ===');
  
  try {
    // 测试连接 - 查询当前用户
    final session = supabase.auth.currentSession;
    print('当前会话: ${session != null ? "已登录" : "未登录"}');
    
    // 尝试查询 profiles 表是否存在
    print('\n=== 检查数据库表 ===');
    try {
      final result = await supabase.from('profiles').select('count').limit(1);
      print('profiles 表: 存在');
    } catch (e) {
      print('profiles 表: 不存在或无法访问');
      print('错误: $e');
    }
    
    try {
      final result = await supabase.from('memories').select('count').limit(1);
      print('memories 表: 存在');
    } catch (e) {
      print('memories 表: 不存在或无法访问');
    }
    
    try {
      final result = await supabase.from('daily_logs').select('count').limit(1);
      print('daily_logs 表: 存在');
    } catch (e) {
      print('daily_logs 表: 不存在或无法访问');
    }
    
    try {
      final result = await supabase.from('memory_embeddings').select('count').limit(1);
      print('memory_embeddings 表: 存在');
    } catch (e) {
      print('memory_embeddings 表: 不存在或无法访问');
    }
    
    try {
      final result = await supabase.from('conversations').select('count').limit(1);
      print('conversations 表: 存在');
    } catch (e) {
      print('conversations 表: 不存在或无法访问');
    }
    
    try {
      final result = await supabase.from('messages').select('count').limit(1);
      print('messages 表: 存在');
    } catch (e) {
      print('messages 表: 不存在或无法访问');
    }

    print('\n=== 检查 pgvector 扩展 ===');
    try {
      // 尝试查询向量表（如果存在的话）
      final result = await supabase.rpc('check_pgvector');
      print('pgvector 扩展: 已启用');
    } catch (e) {
      print('pgvector 扩展: 无法确认状态（需要管理员权限）');
    }

  } catch (e) {
    print('连接错误: $e');
  }

  print('\n=== 结论 ===');
  print('由于安全限制，anon key 无法执行 DDL 操作（创建/删除表）。');
  print('请在 Supabase 控制台手动执行 sql/init.sql 文件。');
  
  exit(0);
}
