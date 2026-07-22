-- ============================================
-- 迁移脚本 008: Timeline 时间线
-- 第二层 Agent 产出：从 Facts 生成 Timeline 事件卡片
-- ============================================

-- ============================================
-- 1. timeline 表
-- ============================================
CREATE TABLE timeline (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
  fact_group_id UUID REFERENCES fact_groups(id) ON DELETE SET NULL,
  title TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  occurred_at TIMESTAMPTZ,
  time_precision TEXT NOT NULL DEFAULT 'unknown',
  icon TEXT,
  event_source TEXT NOT NULL DEFAULT 'chat',
  raw_content TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX timeline_user_id_idx ON timeline(user_id);
CREATE INDEX timeline_user_occurred_at_idx ON timeline(user_id, occurred_at DESC);
CREATE INDEX timeline_time_precision_idx ON timeline(time_precision);
CREATE INDEX timeline_event_source_idx ON timeline(event_source);
CREATE INDEX timeline_created_at_idx ON timeline(created_at DESC);

-- ============================================
-- 2. RLS 行级安全策略
-- ============================================
ALTER TABLE timeline ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的时间线"
  ON timeline FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以创建自己的时间线"
  ON timeline FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "用户可以更新自己的时间线"
  ON timeline FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以删除自己的时间线"
  ON timeline FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================
-- 3. updated_at 触发器
-- ============================================
CREATE TRIGGER update_timeline_updated_at
  BEFORE UPDATE ON timeline
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

SELECT '迁移完成：timeline 表已创建' AS result;
