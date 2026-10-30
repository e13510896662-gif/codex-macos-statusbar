# Codex Flow Implementation Plan

**Goal:** 将已确认的水流设计实现为连接真实数据的 macOS 菜单栏工具。
**Architecture:** FlowCore 负责用量解析、只读任务日志与官方 App Server 协议；AppKit 层负责菜单栏动画和弹出面板。网络与文件读取在串行后台队列执行，界面在主线程更新。
**Tech Stack:** Swift 5.9+, AppKit, Foundation, SQLite3, ServiceManagement；macOS 13+。
**Spec:** design.md

## Global Constraints
- 不复制密钥，不启动模型任务，不修改 Codex 设置、任务或数据库。
- 缺失数据不可视为零，旧数据必须标记；无真实任务百分比时只展示事件状态。
- 仅监测同一个 CODEX_HOME 下近 24 小时的本机任务。

## Review Focus
- 账户只有周额度、缺失窗口、周期已重置、损坏字段。
- 乱序旧 turn 结束、日志截断、半行 JSON、老任务残留。
- 主线程不能阻塞；子进程超时、退出、睡眠恢复后必须可重连。
- 动画尊重减少动态效果；登录启动失败需要显示错误。
- 测试诊断不得输出聊天正文、登录密钥或账户标识。

### Task 1: 额度和任务模型
- [x] 先写单元测试，覆盖服务器字段优先级、周额度、空值、异常值和日志生命周期。
- [x] 运行确认 RED，再实现 Sources/FlowCore/Models.swift 和 Rollout.swift。
- [x] `swift test` 全绿。

### Task 2: 真实数据适配
- [x] 先写文件增量读取与 SQLite 只读集成测试，确认 RED。
- [x] 实现 LocalTasks.swift 与 AppServer.swift，保证超时和资源释放。
- [x] 运行全部测试，并以 `--diagnose` 对真实账户读取验证。

### Task 3: 原生界面和交付
- [x] 实现水流绘制、菜单栏、面板和退出/刷新/启动选项。
- [x] Release 构建为 .app 并 ad-hoc 签名；启动检查菜单栏和面板。
- [x] 最终代码审查，修正重要问题，重新运行全部测试和真实数据诊断。

Pre-flight: Task 2 消费 Task 1 的 UsageSnapshot / TaskState；Task 3 消费监视器快照与 ActivitySummary；所有网络和文件操作离开主线程。

## 发布范围更新

- 用户确认将指标改为剩余额度；0%、100% 和已用 8% → 剩余 92% 已纳入测试。
- v0.0.1 以 MIT 许可公开发布，仓库 codex-macos-statusbar，配置 Issues 需求与缺陷表单。
- 独立审查发现的大日志恢复与退出清理问题已通过失败回归测试验证后修复。
