import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final supabaseKey = env['SUPABASE_ANON_KEY'] ?? '';

  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    print('❌ 请在 .env 文件中配置 SUPABASE_URL 和 SUPABASE_ANON_KEY');
    exit(1);
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  final supabase = Supabase.instance.client;

  print('🔄 开始执行数据库迁移...');

  final sql = '''
-- 1. 给 messages 表添加 extracted 字段
ALTER TABLE messages ADD COLUMN IF NOT EXISTS extracted BOOLEAN DEFAULT FALSE;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS extraction_error TEXT;

-- 2. 创建 extracted_facts 表
CREATE TABLE IF NOT EXISTS extracted_facts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  fact_type TEXT NOT NULL,
  fact_key TEXT NOT NULL,
  fact_value TEXT NOT NULL,
  confidence FLOAT DEFAULT 0.0,
  raw_content TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. 创建索引
CREATE INDEX IF NOT EXISTS extracted_facts_message_id_idx ON extracted_facts(message_id);
CREATE INDEX IF NOT EXISTS extracted_facts_user_id_idx ON extracted_facts(user_id);
CREATE INDEX IF NOT EXISTS extracted_facts_fact_type_idx ON extracted_facts(fact_type);
CREATE INDEX IF NOT EXISTS extracted_facts_created_at_idx ON extracted_facts(created_at DESC);
CREATE INDEX IF NOT EXISTS messages_extracted_idx ON messages(extracted);

-- 4. 给 profiles 表添加 birthday 字段
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS birthday DATE;

-- 5. RLS 行级安全策略
ALTER TABLE extracted_facts ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "用户可以查看自己的事实" ON extracted_facts FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY IF NOT EXISTS "用户可以创建自己的事实" ON extracted_facts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY IF NOT EXISTS "用户可以删除自己的事实" ON extracted_facts FOR DELETE USING (auth.uid() = user_id);

-- 6. 更新触发器
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS \$\$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
\$\$ LANGUAGE plpgsql;

CREATE TRIGGER IF NOT EXISTS update_extracted_facts_updated_at
BEFORE UPDATE ON extracted_facts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
''';

  try {
    await supabase.rpc('_execute_sql', params: {'query': sql});
    print('✅ 数据库迁移完成！');
    
    // 验证
    final tables = await supabase.from('extracted_facts').select().limit(0);
    print('✅ extracted_facts 表已创建');
    
    final result = await supabase.rpc('_execute_sql', params: {'query': 'SELECT extracted FROM messages LIMIT 1'});
    print('✅ messages.extracted 字段已添加');
    
    final profileResult = await supabase.rpc('_execute_sql', params: {'query': 'SELECT birthday FROM profiles LIMIT 1'});
    print('✅ profiles.birthday 字段已添加');
    
  } catch (e) {
    print('❌ 迁移失败: $e');
    exit(1);
  }

  exit(0);
}
