#!/bin/bash
# AIUsageMonitor 内置小说 Web UI — 双击启动
cd "$(dirname "$0")/.."

echo "🚀 小说 Web UI 启动中..."
echo ""

if [ ! -x "web/.venv/bin/python" ]; then
    echo "📦 首次运行，创建虚拟环境并安装依赖..."
    if ! command -v uv &>/dev/null; then
        echo "❌ 未找到 uv，请先安装：curl -LsSf https://astral.sh/uv/install.sh | sh"
        echo "按回车键退出"
        read
        exit 1
    fi
    cd web && uv venv .venv && uv pip install -r requirements.txt && cd ..
fi

# 启动 Flask 服务（后台）
web/.venv/bin/python web/app.py &
FLASK_PID=$!

# 等待服务器就绪
echo "⏳ 等待服务器启动..."
for i in $(seq 1 15); do
    sleep 1
    if curl -s http://localhost:8080/ >/dev/null 2>&1; then
        echo "✅ 服务已就绪"
        break
    fi
done

# 打开浏览器
echo "🌐 打开浏览器..."
open http://localhost:8080
echo "按 Ctrl+C 停止服务"
echo ""

# 保持窗口打开，等待 Flask 退出
wait $FLASK_PID

echo ""
echo "服务已停止"
echo "按回车键关闭窗口"
read
