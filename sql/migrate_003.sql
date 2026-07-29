-- 创建操作日志表
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

-- 创建索引
CREATE INDEX IF NOT EXISTS operation_logs_user_id_idx ON operation_logs(user_id);
CREATE INDEX IF NOT EXISTS operation_logs_status_idx ON operation_logs(status);
CREATE INDEX IF NOT EXISTS operation_logs_created_at_idx ON operation_logs(created_at DESC);

-- RLS 策略
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
