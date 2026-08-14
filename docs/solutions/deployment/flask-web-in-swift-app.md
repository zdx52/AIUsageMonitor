# 将 Flask Web 集成进 Swift 菜单栏 App

**症状**：用户想把 novel-pipeline 的小说 Web UI（Flask）搬进 AIUsageMonitor（Swift 菜单栏 app），并在看板旁加按钮一键打开。

**根因**：无（功能新增）。但 web 服务有 3 个隐式路径依赖，直接复制会跑不起来：
1. `web/app.py` 的 `BASE_DIR = Path(__file__).resolve().parent.parent`——复制后自动指向新项目根，本身不用改；
2. `SCRIPTS_DIR = BASE_DIR / "scripts"`——质检脚本原在 novel-pipeline/scripts/，复制后指向 AIUsageMonitor/scripts/（与 deploy.sh 混在一起），必须改为 `BASE_DIR / "web" / "scripts"` 保持自包含；
3. `NOVELS_PATH`（数据目录）——novel-pipeline/.env 指向 `~/Documents/Hermes/小说创作/novels`，新项目需建自己的 .env 写 `NOVELS_PATH=`（web 的 settings 页会读/写这个 .env，键值保留）。

**修复**：
- `rsync -a --exclude=__pycache__ --exclude=.DS_Store` 复制 web/ → 新项目
- 复制 4 个质检脚本（check_fanqie_quality / check_duplicate_text / scan_cast / check_continuity，全部纯标准库）到 `web/scripts/`
- 改 app.py 一行 `SCRIPTS_DIR`
- `web/requirements.txt`（Flask / Markdown / python-dotenv）+ `uv venv` 建 `web/.venv`（venv 放 web/ 下，不污染 Swift 构建）
- Swift 侧：`NovelWebServer`（Process 管理：探测 8080 → 没跑则 `web/.venv/bin/python web/app.py` 拉起 → 轮询就绪）+ `NovelWebWindowController`（仿 Hindsight 看板，WKWebView 加载 localhost:8080）+ MenuBarView 按钮
- app 退出时 `applicationWillTerminate` 只 terminate 自己拉起的进程（不碰外部已运行实例）

**预防**：
- 双击启动脚本（.command）不能用 `uv run python web/app.py`（新项目根无 pyproject.toml，uv run 会失败），必须显式 `web/.venv/bin/python web/app.py`
- deploy.sh 只打包 Swift 二进制，web/ 走源码目录绝对路径（`~/Documents/Hermes/AIUsageMonitor/web`），UserDefaults 键 `novelWebProjectPath` 可覆盖——.app 分发不含 web
- 端口固定 8080（与 Hindsight 9999 不冲突）；app.py 里 `host="0.0.0.0"` 不改
- 版本号五处同步后必须 deploy.sh（含 CFBundleVersion +1）

**UI 美化坑（2026-08-14）**：
- **Jinja block 变量不可见**：`{% set %}` 在 `{% block content %}` 内定义，`{% block scripts %}` 取不到（渲染为空白）。block 内用到 set 变量必须在该 block 内重新 set。
- **章节路由缺 chapters 变量**（迁移前原有 bug）：`render_template` 只传 vol_groups/total_chars/config，模板 `{{ chapters|length }}` 显示 0 章，需补传 `chapters=chapters`。
- **SVG + CSS 变量**：WKWebView（WebKit）里 SVG presentation attribute（setAttribute('stroke', 'var(--accent)')）不可靠，必须用 `el.style.stroke = 'var(--accent)'` 才能解析 CSS 变量。
- **SVG 图表用 JS 从 `{{ chapters|tojson }}` 渲染**：零依赖、80 点也流畅；底部标签稀疏显示（step = ceil(n/8)）避免密集文字。
- **验证链路**：curl 验状态码 → headless Chrome 截图（`--headless --screenshot --window-size`）→ vision 检查渲染；browser_exec 工具在本机已坏（pydantic_core 缺编译模块），不用。
