#!/bin/bash
# Vercel 构建环境安装 Flutter SDK(在 Vercel 服务器执行,不是用户本地)
set -e

FLUTTER_DIR=${FLUTTER_DIR:-/tmp/flutter}

if [ ! -d "$FLUTTER_DIR/.git" ]; then
  echo ">> 克隆 Flutter SDK(stable,浅克隆)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
else
  echo ">> Flutter SDK 已存在,跳过克隆"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

echo ">> Flutter 版本:"
flutter --version

echo ">> 预缓存 Web 工具..."
flutter precache --web

echo ">> 安装 Dart 依赖..."
flutter pub get

echo ">> Flutter 环境就绪"
