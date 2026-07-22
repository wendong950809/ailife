-- ============================================
-- 迁移 006: 添加 AI 设置字段到 profiles 表
-- ============================================

-- 添加 AI 名称字段
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS ai_name TEXT;

-- 添加 AI 头像 URL 字段
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS ai_avatar_url TEXT;

-- 添加用户昵称字段
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS nickname TEXT;

-- 设置默认值
UPDATE profiles SET ai_name = '知伴' WHERE ai_name IS NULL;
