#!/bin/bash
# Vercel 构建脚本：安装 Flutter + build web（在同一 shell 中执行，确保 PATH 可用）
set -e

FLUTTER_DIR=${FLUTTER_DIR:-/tmp/flutter}

# 1. 安装 Flutter SDK（如果还没装）
if [ ! -f "$FLUTTER_DIR/bin/flutter" ]; then
  echo ">> 克隆 Flutter SDK(stable,浅克隆)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
else
  echo ">> Flutter SDK 已存在,跳过克隆"
fi

# 2. 设置 PATH（关键：必须在同一脚本中 export，新 shell 才能用）
export PATH="$FLUTTER_DIR/bin:$PATH"

# 3. 验证 Flutter
echo ">> Flutter 版本:"
flutter --version

# 4. 预缓存 Web 工具
echo ">> 预缓存 Web 工具..."
flutter precache --web

# 5. 安装 Dart 依赖
echo ">> 安装 Dart 依赖..."
flutter pub get

# 6. 创建空的 .env 文件（避免 dotenv 加载失败）
touch .env

# 7. Build web，用 --dart-define 注入环境变量
echo ">> 开始 build web..."
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=DEEPSEEK_API_KEY="$DEEPSEEK_API_KEY" \
  --dart-define=OPENAI_API_KEY="$OPENAI_API_KEY"

echo ">> Build 完成！"
