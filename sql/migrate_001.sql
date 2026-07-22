-- ============================================
-- 迁移脚本 001
-- 添加 extracted_facts 表 + messages.extracted 字段 + profiles.birthday 字段
-- 在 Supabase SQL Editor 中执行
-- ============================================

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

-- 策略（先删除已有再创建，避免重复报错）
DROP POLICY IF EXISTS "用户可以查看自己的事实" ON extracted_facts;
CREATE POLICY "用户可以查看自己的事实" ON extracted_facts FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "用户可以创建自己的事实" ON extracted_facts;
CREATE POLICY "用户可以创建自己的事实" ON extracted_facts FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "用户可以删除自己的事实" ON extracted_facts;
CREATE POLICY "用户可以删除自己的事实" ON extracted_facts FOR DELETE USING (auth.uid() = user_id);

-- 6. 更新触发器函数
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_extracted_facts_updated_at ON extracted_facts;
CREATE TRIGGER update_extracted_facts_updated_at
  BEFORE UPDATE ON extracted_facts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 验证
SELECT '迁移完成' AS result;
