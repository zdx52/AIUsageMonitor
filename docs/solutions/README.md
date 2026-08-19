# AIUsageMonitor Solutions

项目经验沉淀库（Compound Engineering 模式）。

每次修完 bug / 踩完坑 / 定下约定，把"症状 → 根因 → 修复 → 预防"写成一篇文章放在这里。
下一个 agent（或未来的自己）开工前先读这里，避免重复踩坑。

## 索引

| 文档 | 类型 | 主题 |
| --- | --- | --- |
| [git-push-release-workflow.md](workflow/git-push-release-workflow.md) | 工作流 | Git 推送三件套 + Release 三件套 |
| [web-new-style-novel-structure.md](workflow/web-new-style-novel-structure.md) | 架构模式 | Web 前端兼容新开书结构（设定/大纲/追踪 目录 fallback） |
| [app-bundle-deploy.md](deployment/app-bundle-deploy.md) | 工具决策 | deploy.sh 一键部署 + 版本号同步 |
| [keychain-acl-resign.md](deployment/keychain-acl-resign.md) | Bug 排查 | ad-hoc 重签名使 keychain ACL 失联 → SecItemCopyMatching 阻塞 securityd，填 key 无效 |
| [flask-web-in-swift-app.md](deployment/flask-web-in-swift-app.md) | 架构决策 | Flask web 集成进 Swift 菜单栏 app（路径依赖/venv/进程管理） |
| [dock-window-presence.md](deployment/dock-window-presence.md) | 架构模式 | 菜单栏 app 窗口开→Dock 图标出现、全关→消失（activationPolicy 动态切换） |
| [github-auth-token.md](tooling/github-auth-token.md) | 工具决策 | GITHUB_TOKEN / gh CLI 认证方式 |
| [repo-format-conventions.md](conventions/repo-format-conventions.md) | 约定 | README/About/版本号格式规范 |
