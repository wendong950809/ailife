CREATE TABLE IF NOT EXISTS ai_call_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  call_type TEXT NOT NULL,
  model TEXT NOT NULL,
  provider TEXT NOT NULL,
  prompt TEXT,
  system_prompt_preview TEXT,
  response TEXT,
  prompt_tokens INT DEFAULT 0,
  completion_tokens INT DEFAULT 0,
  total_tokens INT DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'success',
  error_message TEXT,
  latency_ms INT,
  temperature FLOAT,
  extra TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ai_call_logs_user_id_idx ON ai_call_logs(user_id);
CREATE INDEX IF NOT EXISTS ai_call_logs_call_type_idx ON ai_call_logs(call_type);
CREATE INDEX IF NOT EXISTS ai_call_logs_status_idx ON ai_call_logs(status);
CREATE INDEX IF NOT EXISTS ai_call_logs_created_at_idx ON ai_call_logs(created_at DESC);

ALTER TABLE ai_call_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的AI调用日志"
  ON ai_call_logs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以创建自己的AI调用日志"
  ON ai_call_logs FOR INSERT
  WITH CHECK (auth.uid() = user_id);

SELECT '迁移完成' AS result;
