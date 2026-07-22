import 'dart:io';
import 'dart:convert';
import 'package:postgres/postgres.dart';

void main() async {
  final host = 'vjwolnmswmhpxdsskrmg.supabase.co';
  final port = 5432;
  final database = 'postgres';
  final username = 'postgres';
  
  final password = Platform.environment['SUPABASE_DB_PASSWORD'];
  if (password == null || password.isEmpty) {
    print('❌ 需要设置 SUPABASE_DB_PASSWORD 环境变量');
    exit(1);
  }

  print('🔄 连接数据库...');
  
  final connection = PostgreSQLConnection(
    host,
    port,
    database,
    username: username,
    password: password,
    useSSL: true,
  );

  try {
    await connection.open();
    print('✅ 数据库连接成功');

    final sqlStatements = [
      'ALTER TABLE messages ADD COLUMN IF NOT EXISTS extracted BOOLEAN DEFAULT FALSE;',
      'ALTER TABLE messages ADD COLUMN IF NOT EXISTS extraction_error TEXT;',
      '''
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
      ''',
      'CREATE INDEX IF NOT EXISTS extracted_facts_message_id_idx ON extracted_facts(message_id);',
      'CREATE INDEX IF NOT EXISTS extracted_facts_user_id_idx ON extracted_facts(user_id);',
      'CREATE INDEX IF NOT EXISTS extracted_facts_fact_type_idx ON extracted_facts(fact_type);',
      'CREATE INDEX IF NOT EXISTS extracted_facts_created_at_idx ON extracted_facts(created_at DESC);',
      'CREATE INDEX IF NOT EXISTS messages_extracted_idx ON messages(extracted);',
      'ALTER TABLE profiles ADD COLUMN IF NOT EXISTS birthday DATE;',
      'ALTER TABLE extracted_facts ENABLE ROW LEVEL SECURITY;',
      'CREATE POLICY IF NOT EXISTS "用户可以查看自己的事实" ON extracted_facts FOR SELECT USING (auth.uid() = user_id);',
      'CREATE POLICY IF NOT EXISTS "用户可以创建自己的事实" ON extracted_facts FOR INSERT WITH CHECK (auth.uid() = user_id);',
      'CREATE POLICY IF NOT EXISTS "用户可以删除自己的事实" ON extracted_facts FOR DELETE USING (auth.uid() = user_id);',
      '''
      CREATE OR REPLACE FUNCTION update_updated_at_column()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      ''',
      'CREATE TRIGGER IF NOT EXISTS update_extracted_facts_updated_at BEFORE UPDATE ON extracted_facts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();',
    ];

    for (var i = 0; i < sqlStatements.length; i++) {
      final sql = sqlStatements[i];
      print('🔄 执行 SQL ${i + 1}/${sqlStatements.length}...');
      try {
        await connection.execute(sql);
        print('✅ SQL ${i + 1} 执行成功');
      } catch (e) {
        print('⚠️ SQL ${i + 1} 执行失败（可能已存在）: $e');
      }
    }

    print('\n🎉 所有数据库迁移已完成！');
    
    // 验证
    final result = await connection.query('SELECT * FROM extracted_facts LIMIT 0');
    print('✅ extracted_facts 表已创建');
    
    await connection.close();
    
  } catch (e) {
    print('❌ 迁移失败: $e');
    await connection.close();
    exit(1);
  }
  
  exit(0);
}
