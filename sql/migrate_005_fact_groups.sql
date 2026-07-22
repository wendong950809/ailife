-- ============================================
-- 迁移脚本 005: 引入 Fact Group 机制
-- 核心变化: Message → Fact Group → Facts
-- 1. 新增 fact_groups 表
-- 2. extracted_facts 增加 fact_group_id 字段
-- 3. fact_type 中立化改造（保持旧数据兼容，新数据用新类型）
-- ============================================

-- ============================================
-- 1. fact_groups - 事实组表
-- ============================================
CREATE TABLE fact_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  summary TEXT NOT NULL DEFAULT '',
  fact_count INTEGER NOT NULL DEFAULT 0,
  raw_content TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX fact_groups_message_id_idx ON fact_groups(message_id);
CREATE INDEX fact_groups_user_id_idx ON fact_groups(user_id);
CREATE INDEX fact_groups_created_at_idx ON fact_groups(created_at DESC);

-- ============================================
-- 2. extracted_facts 增加 fact_group_id 字段
-- ============================================
ALTER TABLE extracted_facts ADD COLUMN fact_group_id UUID REFERENCES fact_groups(id) ON DELETE CASCADE;

CREATE INDEX extracted_facts_fact_group_id_idx ON extracted_facts(fact_group_id);

-- ============================================
-- 3. RLS 行级安全策略（fact_groups）
-- ============================================
ALTER TABLE fact_groups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的事实组"
  ON fact_groups FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以创建自己的事实组"
  ON fact_groups FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "用户可以删除自己的事实组"
  ON fact_groups FOR DELETE
  USING (auth.uid() = user_id);

-- extracted_facts 的 RLS 补充：通过 fact_group_id 关联的也应允许（当前已有 user_id 判断，保持不变）

-- ============================================
-- 4. updated_at 触发器
-- ============================================
CREATE TRIGGER update_fact_groups_updated_at
  BEFORE UPDATE ON fact_groups
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 5. 迁移历史数据（为已有 facts 创建对应的 fact_group）
--    每条用户消息对应一个 fact_group
-- ============================================
DO $$
DECLARE
  msg RECORD;
  group_id UUID;
BEGIN
  FOR msg IN
    SELECT DISTINCT m.id, m.user_id, m.content
    FROM messages m
    JOIN extracted_facts ef ON ef.message_id = m.id
    WHERE m.role = 'user'
  LOOP
    -- 创建 fact_group
    INSERT INTO fact_groups (message_id, user_id, summary, fact_count)
    VALUES (msg.id, msg.user_id, substring(msg.content, 1, 100),
            (SELECT COUNT(*) FROM extracted_facts WHERE message_id = msg.id))
    RETURNING id INTO group_id;

    -- 把该消息下所有 facts 关联到这个 group
    UPDATE extracted_facts
    SET fact_group_id = group_id
    WHERE message_id = msg.id;
  END LOOP;
END $$;
