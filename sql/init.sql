-- ============================================
-- AI Life 数据库初始化脚本
-- 说明：先清理所有旧表，再重新创建
-- ============================================

-- 启用 pgvector 扩展
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================
-- 清理旧表（按依赖关系逆序删除）
-- ============================================
DROP TABLE IF EXISTS memory_embeddings CASCADE;
DROP TABLE IF EXISTS memories CASCADE;
DROP TABLE IF EXISTS daily_logs CASCADE;
DROP TABLE IF EXISTS conversations CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

-- ============================================
-- 1. profiles - 用户资料表
-- ============================================
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE,
  avatar_url TEXT,
  bio TEXT,
  birthday DATE,
  ai_name TEXT DEFAULT '知伴',
  ai_avatar_url TEXT,
  nickname TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 2. memories - 记忆表
-- ============================================
CREATE TABLE memories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  category TEXT DEFAULT 'general',
  tags TEXT[] DEFAULT '{}',
  importance INTEGER DEFAULT 5,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX memories_user_id_idx ON memories(user_id);
CREATE INDEX memories_category_idx ON memories(category);
CREATE INDEX memories_created_at_idx ON memories(created_at DESC);

-- ============================================
-- 3. memory_embeddings - 记忆向量表
-- ============================================
CREATE TABLE memory_embeddings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  memory_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  embedding vector(1536) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX memory_embeddings_memory_id_idx ON memory_embeddings(memory_id);
CREATE INDEX memory_embeddings_user_id_idx ON memory_embeddings(user_id);
CREATE INDEX memory_embeddings_embedding_idx ON memory_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ============================================
-- 4. daily_logs - 每日日志表
-- ============================================
CREATE TABLE daily_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  log_date DATE NOT NULL,
  mood INTEGER DEFAULT 3,
  weather TEXT,
  highlights TEXT[] DEFAULT '{}',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, log_date)
);

CREATE INDEX daily_logs_user_id_idx ON daily_logs(user_id);
CREATE INDEX daily_logs_log_date_idx ON daily_logs(log_date DESC);

-- ============================================
-- 5. conversations - 对话记录表
-- ============================================
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT '新对话',
  last_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX conversations_user_id_idx ON conversations(user_id);
CREATE INDEX conversations_updated_at_idx ON conversations(updated_at DESC);

-- ============================================
-- 6. messages - 消息表
-- ============================================
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT NOT NULL,
  tokens INTEGER DEFAULT 0,
  extracted BOOLEAN DEFAULT FALSE,
  extraction_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX messages_conversation_id_idx ON messages(conversation_id);
CREATE INDEX messages_created_at_idx ON messages(created_at ASC);
CREATE INDEX messages_extracted_idx ON messages(extracted);

-- ============================================
-- 7. extracted_facts - 结构化事实提取表
-- ============================================
CREATE TABLE extracted_facts (
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

CREATE INDEX extracted_facts_message_id_idx ON extracted_facts(message_id);
CREATE INDEX extracted_facts_user_id_idx ON extracted_facts(user_id);
CREATE INDEX extracted_facts_fact_type_idx ON extracted_facts(fact_type);
CREATE INDEX extracted_facts_created_at_idx ON extracted_facts(created_at DESC);

-- ============================================
-- RLS 行级安全策略
-- ============================================

-- profiles 表策略
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的资料"
  ON profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "用户可以更新自己的资料"
  ON profiles FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "用户可以插入自己的资料"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- memories 表策略
ALTER TABLE memories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的记忆"
  ON memories FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以创建自己的记忆"
  ON memories FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "用户可以更新自己的记忆"
  ON memories FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以删除自己的记忆"
  ON memories FOR DELETE
  USING (auth.uid() = user_id);

-- memory_embeddings 表策略
ALTER TABLE memory_embeddings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的向量"
  ON memory_embeddings FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以创建自己的向量"
  ON memory_embeddings FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "用户可以删除自己的向量"
  ON memory_embeddings FOR DELETE
  USING (auth.uid() = user_id);

-- daily_logs 表策略
ALTER TABLE daily_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的日志"
  ON daily_logs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以创建自己的日志"
  ON daily_logs FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "用户可以更新自己的日志"
  ON daily_logs FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以删除自己的日志"
  ON daily_logs FOR DELETE
  USING (auth.uid() = user_id);

-- conversations 表策略
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的对话"
  ON conversations FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以创建自己的对话"
  ON conversations FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "用户可以更新自己的对话"
  ON conversations FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以删除自己的对话"
  ON conversations FOR DELETE
  USING (auth.uid() = user_id);

-- messages 表策略
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的消息"
  ON messages FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以创建自己的消息"
  ON messages FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- extracted_facts 表策略
ALTER TABLE extracted_facts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看自己的事实"
  ON extracted_facts FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "用户可以创建自己的事实"
  ON extracted_facts FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "用户可以删除自己的事实"
  ON extracted_facts FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================
-- 自动更新 updated_at 的触发器函数
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 为各表添加触发器
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_memories_updated_at
  BEFORE UPDATE ON memories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_daily_logs_updated_at
  BEFORE UPDATE ON daily_logs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_conversations_updated_at
  BEFORE UPDATE ON conversations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_extracted_facts_updated_at
  BEFORE UPDATE ON extracted_facts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 新用户注册时自动创建 profile 的触发器
-- ============================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, username)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1)));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();
