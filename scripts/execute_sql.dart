import 'dart:io';
import 'dart:convert';

void main() async {
  // 从环境变量或输入获取 service_role key
  final serviceKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  
  if (serviceKey == null || serviceKey.isEmpty) {
    print('❌ 需要设置 SUPABASE_SERVICE_ROLE_KEY 环境变量');
    print('请从 Supabase Dashboard 获取服务端密钥');
    exit(1);
  }

  final url = 'https://vjwolnmswmhpxdsskrmg.supabase.co/rest/v1/rpc/_execute_sql';
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $serviceKey',
    'apikey': serviceKey,
  };

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

-- 验证
SELECT '迁移完成' AS result;
''';

  print('🔄 开始执行数据库迁移...');
  
  try {
    final httpClient = HttpClient();
    final request = await httpClient.postUrl(Uri.parse(url));
    
    headers.forEach((key, value) {
      request.headers.add(key, value);
    });
    
    request.write(jsonEncode({'query': sql}));
    
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    
    if (response.statusCode == 200) {
      print('✅ 数据库迁移完成！');
      print('响应: $responseBody');
    } else {
      print('❌ 迁移失败，状态码: ${response.statusCode}');
      print('响应: $responseBody');
      exit(1);
    }
    
    httpClient.close();
  } catch (e) {
    print('❌ 迁移异常: $e');
    exit(1);
  }
  
  exit(0);
}
