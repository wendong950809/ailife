import 'dart:io';
import 'dart:convert';

void main() async {
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
CREATE TABLE IF NOT EXISTS operation_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  operation_type TEXT NOT NULL,
  target_table TEXT NOT NULL,
  target_id TEXT,
  status TEXT NOT NULL,
  message TEXT,
  request_data JSONB,
  response_data JSONB,
  error_details TEXT,
  duration_ms INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS operation_logs_user_id_idx ON operation_logs(user_id);
CREATE INDEX IF NOT EXISTS operation_logs_status_idx ON operation_logs(status);
CREATE INDEX IF NOT EXISTS operation_logs_created_at_idx ON operation_logs(created_at DESC);

ALTER TABLE operation_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的操作日志"
  ON operation_logs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以创建自己的操作日志"
  ON operation_logs FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "用户可以删除自己的操作日志"
  ON operation_logs FOR DELETE
  USING (auth.uid() = user_id);

UPDATE messages 
SET extracted = true 
WHERE id IN (SELECT DISTINCT message_id FROM extracted_facts) 
  AND extracted = false;

SELECT '迁移完成' AS result;
''';

  print('🔄 开始执行数据库迁移 004...');
  
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
      print('✅ 数据库迁移 004 完成！');
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