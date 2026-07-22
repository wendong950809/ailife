-- 修复 messages 表缺少 UPDATE RLS 策略的问题
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以更新自己的消息"
  ON messages FOR UPDATE
  USING (auth.uid() = user_id);

-- 给 extracted_facts 表也添加 UPDATE 策略
ALTER TABLE extracted_facts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以更新自己的事实"
  ON extracted_facts FOR UPDATE
  USING (auth.uid() = user_id);
