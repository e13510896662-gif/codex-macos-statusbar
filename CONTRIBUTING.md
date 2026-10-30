# 参与贡献

欢迎提交功能建议、缺陷报告、文档改进和 Pull Request。

## 需求与问题

- 功能建议：使用仓库 Issues 中的「更新需求」表单。
- 缺陷：说明应用版本、macOS 版本、Mac 架构、Codex 版本和复现步骤。
- 请先搜索已有 Issues，避免同一需求重复分散。
- 不要公开原始聊天日志、认证文件、账户标识或凭据。诊断摘要也应在发布前自行检查。

## 开发

```bash
bash test.sh
bash build.sh
```

数据和协议逻辑位于 `Sources/FlowCore`，界面位于 `Sources/CodexFlow`，回归测试位于 `Tests/FlowCoreTests`。

修改额度或状态判断时，请先添加能够复现问题的测试。测试使用独立临时数据，不得依赖贡献者的真实 Codex 数据或登录。

Pull Request 请说明用户可见的变化、修改理由及验证方式。涉及本地存储、网络、自动启动或权限范围时，请清楚描述变化。

提交内容以本仓库 MIT 许可分发。
