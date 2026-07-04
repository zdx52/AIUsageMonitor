#!/bin/bash
# deploy.sh — 构建 + 部署 AIUsageMonitor .app
# 用法: ./scripts/deploy.sh
# 要求: 从项目根目录执行

set -euo pipefail

cd "$(dirname "$0")/.."

echo "🔨 构建 release..."
swift build -c release

APP_BUNDLE="/Applications/AIUsageMonitor.app"
BUILD_BIN=".build/release/AIUsageMonitor"

echo "📦 复制二进制..."
cp "$BUILD_BIN" "$APP_BUNDLE/Contents/MacOS/AIUsageMonitor"

echo "📄 复制 Info.plist..."
cp AIUsageMonitor/Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "🎨 复制资源文件..."
cp AIUsageMonitor/Resources/hindsight-dashboard.html "$APP_BUNDLE/Contents/Resources/hindsight-dashboard.html"
cp AIUsageMonitor/Resources/hindsight-server.py "$APP_BUNDLE/Contents/Resources/hindsight-server.py"

echo "✍️ 签名..."
codesign --force --sign - "$APP_BUNDLE"

echo "🔄 重启应用..."
killall AIUsageMonitor 2>/dev/null || true
sleep 1
open "$APP_BUNDLE"

echo "✅ 部署完成 (version: $(defaults read "$APP_BUNDLE/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?'))"
