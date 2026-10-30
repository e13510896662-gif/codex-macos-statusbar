# codex Mac系统状态栏

**在 Mac 顶部菜单栏，用一颗流动的水球查看 Codex 剩余额度和本机任务活动。**

[下载 v0.0.1](https://github.com/e13510896662-gif/codex-macos-statusbar/releases/tag/v0.0.1) · [提交更新需求](https://github.com/e13510896662-gif/codex-macos-statusbar/issues/new?template=feature_request.yml) · [报告问题](https://github.com/e13510896662-gif/codex-macos-statusbar/issues/new?template=bug_report.yml)

原生 Swift / AppKit 开发，无 Electron、无网页常驻、无第三方运行时依赖。个人开源项目，与 OpenAI 无隶属关系。

## 它显示什么

菜单栏常驻 **`◉ 92%`**：圆形水位和右侧数字都表示**剩余额度**。服务器返回已用 8% 时，工具显示剩余 92%；100% 水位最高，0% 水位最低。

颜色和流速由本机任务事件驱动，与额度百分比独立：

| 状态 | 视觉表现 | 含义 |
| --- | --- | --- |
| 空闲 | 绿色、缓慢水流 | 最近监测到的任务已经结束，或暂无任务 |
| 执行中 | 黄绿色 → 黄色 → 橙色、水流加快 | 1–3 个最近有活动的本机任务 |
| 繁忙 | 红色、快速水流 | 4 个及以上最近有活动的本机任务 |
| 等待你 | 橙色、暂停水流 | 日志明确记录需要用户输入或批准 |
| 已完成 | 绿色、短暂对勾 | 收到任务完成事件，保持约 15 秒 |
| 状态待确认 | 灰色、暂停水流 | 未结束任务超过 3 分钟没有新日志 |

**百分比不是任务完成进度。** 工具没有编造任务完成百分比，也不会把长时间无输出直接当作完成。颜色代表观察到的本机任务并行程度，不是 CPU 占用率、Token 速度或 OpenAI 服务负载。

## 运行要求

- macOS 13 或更新版本。
- 已安装并登录官方 Codex 桌面应用，或已使用 ChatGPT 账户登录 Codex CLI。
- v0.0.1 下载包为 **Apple Silicon / arm64**，适用于 M 系列 Mac；Intel Mac 请从源码编译。本版本尚未在 Intel 真机验证。
- 需要联网刷新额度。仅 API Key 登录时，服务端可能不提供 ChatGPT 订阅额度，工具会显示额度不可用。

## 安装

1. 打开 [v0.0.1 Release](https://github.com/e13510896662-gif/codex-macos-statusbar/releases/tag/v0.0.1)，下载 `codex-macos-statusbar-v0.0.1-arm64.zip`。
2. 解压，将 **Codex Mac 状态栏.app** 拖到 **Applications / 应用程序**。
3. 双击打开。应用只出现在顶部菜单栏，**没有 Dock 图标**。
4. 等待首次额度读取完成；通常数秒，网络不佳时最多等待约 25 秒后显示重试提示。

此版本使用本地 ad-hoc 签名，尚未进行 Apple Developer ID 签名或公证。下载后 macOS 可能要求你在“系统设置 → 隐私与安全性”中确认打开；确认来源后由你在系统界面操作。也可以使用下方源码构建方式。

下载包旁提供 `SHA256SUMS.txt`，可在下载目录运行：

```bash
shasum -a 256 -c SHA256SUMS.txt
```

## 使用方法

点击菜单栏的水球或百分比，展开面板：

- **剩余额度**：显示实际额度周期、剩余百分比、重置倒计时和最近更新时间。
- **切换周期**：账户同时返回多个额度窗口时，可在面板中切换；默认选择时长最短的窗口。如果账户只返回每周额度，就只显示每周，不会补造 5 小时额度。
- **任务活动**：显示本机执行中的任务数量、最近活动描述和任务名称。
- **刷新用量**：立即尝试重新读取；已有请求在执行时会合并，避免重复连接。
- **打开 Codex**：跳转到最新的本机活动任务；暂无活动任务时打开 Codex。
- **减少动画**：手动降低动态效果；同时尊重 macOS 的系统“减少动态效果”设置。
- **登录时启动**：默认关闭。打开后可能需要在“系统设置 → 通用 → 登录项”中批准。
- **退出**：关闭工具，并结束它自己启动的只读数据连接进程。

额度默认每 **60 秒**刷新一次，任务日志每 **2 秒**检查一次。用量读取失败、数据超过 150 秒未更新，或额度重置时间已到时，水球出现橙色提示点，面板标记“上次剩余”；该数值不应当作当前最新余额。

## 数据来源、隐私与限制

| 数据 | 来源 | 权限与范围 |
| --- | --- | --- |
| 账户额度 | Codex App Server 的 `account/rateLimits/read` | 复用 Codex 既有登录；只发送初始化和读取请求 |
| 本机任务 | `CODEX_HOME` 内的 `state_*.sqlite` 与任务 JSONL | 数据库以只读模式打开，日志增量读取 |
| 工具偏好 | macOS UserDefaults | 保存周期选择、动画偏好与首次启动标记 |

- 工具自身不读取、复制或上传 `auth.json`、API Key、登录 Token；认证由官方 Codex 进程处理。
- 不启动模型任务，不消耗模型生成 Token，不修改 Codex 任务、数据库或配置。正常网络流量由官方 Codex 子进程用于身份验证及额度查询。
- 不设置自己的分析服务、遥测或第三方数据接收端。
- 本机监测范围为**当前 `CODEX_HOME` 下最近 24 小时更新、未归档的任务**。默认位置为 `~/.codex`。
- 独立 App Server 看不到其他进程中线程的实时加载状态，因此不把其 `notLoaded` 字段当作空闲；任务活动根据本机事件恢复。
- **云端、远程主机及其他 `CODEX_HOME` 下的任务不在范围内。** Codex 本地日志并不保证包含每一种等待事件，因此无法保证识别所有等待用户操作的情况。
- 本地数据库和日志属于兼容适配点，未来 Codex 更新可能改变格式。读取异常时显示不可用并自动重试。

接口参考：[OpenAI 官方 Codex App Server 文档](https://learn.chatgpt.com/docs/app-server)。

## 从源码构建

安装 Xcode 或 Apple Command Line Tools，需要 Swift 5.9 或更新版本。运行自动测试还需要提供 Swift Testing 的较新 Xcode / Command Line Tools（建议 Swift 6+）。

```bash
git clone https://github.com/e13510896662-gif/codex-macos-statusbar.git
cd codex-macos-statusbar

# 编译、打包并本地签名
bash build.sh

# 启动
open "dist/Codex Mac 状态栏.app"
```

将构建产物拖入 Applications 后，可正常设置登录时启动。

```bash
# 测试：额度解析、剩余转换、任务生命周期、日志增量、超时与退出清理
bash test.sh

# 真实账户只读诊断：输出额度与任务数量，不输出聊天正文或账户标识
"dist/Codex Mac 状态栏.app/Contents/MacOS/CodexFlow" --diagnose
```

### 自定义 CLI 或 Codex 数据目录

工具会自动查找官方桌面应用内置 CLI、Homebrew、`~/.local/bin` 与 `PATH`。特殊安装可从终端直接启动并传递环境变量：

```bash
CODEX_FLOW_CLI="/absolute/path/to/codex" \
CODEX_HOME="/absolute/path/to/codex-home" \
"dist/Codex Mac 状态栏.app/Contents/MacOS/CodexFlow"
```

环境变量需要在进程启动前提供；修改后先退出已运行的状态栏工具，再重新启动。

## 常见问题

**打开后看不到窗口？**

这是菜单栏应用，请找屏幕顶部的圆形水球。菜单栏项目很多时，可能被刘海区域或其他菜单栏管理工具隐藏，可按住 Command 拖动图标调整位置。

**显示“额度不可用”？**

先打开官方 Codex，确认账户已登录，再点击刷新；检查网络和 CLI 是否可用。API Key 账户或服务端未提供额度字段时，不会显示虚构数字。可运行 `--diagnose` 查看错误摘要。

**Codex 明明在运行，工具却显示“状态待确认”？**

某些长工具调用、日志写入延迟或异常退出会让日志暂时停更。工具不会凭时间认定任务已完成；收到新事件后会继续更新。也请确认任务运行在同一个本机数据目录中。

**显示的剩余额度和 Codex 不一致？**

先确认比较的是同一额度周期，再手动刷新。工具以账户接口返回值为准，未读取到新数据时会标注旧数据。重置时也不会擅自把旧值改成 100%。

**怎样更新或卸载？**

更新：先从面板退出，下载新版本并替换 Applications 内的应用，再重新打开。卸载：先关闭“登录时启动”，退出后将应用移到废纸篓。工具不会删除或修改 Codex 数据。

## 收集更新需求

欢迎通过 [功能需求表单](https://github.com/e13510896662-gif/codex-macos-statusbar/issues/new?template=feature_request.yml) 提交：

1. 你遇到的具体使用场景。
2. 当前哪里不方便，希望看到什么行为。
3. 是否愿意协助验证，以及 Mac 架构 / macOS / Codex 版本。

已有相同需求请在对应 Issue 上用 👍 表态，便于整理优先级。提交问题时请勿上传原始会话、`auth.json`、Token 或其他敏感信息。

需求以 Issues 为准，规划见 [ROADMAP.md](ROADMAP.md)，提交方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 版本与许可

当前版本：**v0.0.1**。更新记录见 [CHANGELOG.md](CHANGELOG.md)。

[MIT License](LICENSE)。
