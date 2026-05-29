# Codex OpenCode Worker Workflow

一个本地个人级 Codex skill。目标是尽可能减少 Codex 的 token/费用消耗，同时让 Codex 用自己的推理能力为 OpenCode/DeepSeek 写出高质量施工方案。实际读仓库、改代码、跑验证的高消耗工作交给 OpenCode worker。

默认运行方式是后台启动 worker：Codex 创建任务单并启动 OpenCode 后立刻返回 runDir、PID 和日志路径，不陪 DeepSeek 慢慢跑，也不主动检查进度、读取日志、验证或总结。

仓库地址：[ysj98/Codex-OpenCode-Worker-Workflow](https://github.com/ysj98/Codex-OpenCode-Worker-Workflow)

## 它解决什么问题

传统让 Codex 直接实现任务时，消耗通常集中在：

- 大范围读取项目上下文
- 设计实现细节
- 修改代码
- 等待测试和修复
- 复核最终 diff

这个 workflow 把分工改成：

- **Codex**：做少量定向侦察，写施工级 `AI-DEV-TASK.md`，后台启动 worker，然后停止。
- **OpenCode worker 模型**：大量读取、搜索、实现，并运行聚焦且耗时可控的验证命令。
- **用户**：稍后人工查看 `git diff`、确认效果，并决定是否 `git add/commit/push`。

## 快速开始

### 1. 安装 skill

```powershell
git clone https://github.com/ysj98/Codex-OpenCode-Worker-Workflow.git `
  "$HOME\.codex\skills\Codex-OpenCode-Worker-Workflow"
```

### 2. 安装 OpenCode worker agent

```powershell
New-Item -ItemType Directory -Force "$HOME\.config\opencode\agents" | Out-Null

Copy-Item `
  "$HOME\.codex\skills\Codex-OpenCode-Worker-Workflow\opencode\agents\codex-worker.md" `
  "$HOME\.config\opencode\agents\codex-worker.md" `
  -Force
```

### 3. 确认 OpenCode 模型可用

先在 OpenCode 中连接供应商：

```text
/connect
deepseek
```

再确认模型 ID：

```powershell
opencode models deepseek --verbose
```

默认配置期望可用：

```text
deepseek/deepseek-v4-pro
```

## 使用方式

在任意 Git 项目中对 Codex 说：

```text
使用 Codex OpenCode Worker Workflow，帮我实现这个需求：
...
```

或使用机器触发名：

```text
使用 $codex-opencode-worker-workflow，帮我实现这个需求：
...
```

Codex 会读取少量关键文件，生成施工级 `AI-DEV-TASK.md`，再后台调用 OpenCode worker。你会立即拿到 runDir、PID、任务单和日志路径。

## 省 Codex token 的关键约束

- Codex 默认只做 `guided` 侦察：指导文件、manifest/config，以及最多 5 个明显相关文件。
- 小任务可用 `fast`：只读指导文件和 manifest/config。
- 风险任务才用 `deep-plan`：最多 12 个相关文件。
- Codex 不直接改代码，不做全仓扫描，不等待 worker 完成，不主动检查进度，不复核最终 diff。
- worker 启动后，Codex 不读取日志、不验证、不总结 worker 进度。
- OpenCode/DeepSeek 可以大量消耗 token 做仓库阅读、搜索、实现和验证。

## 检查 worker 状态

默认不检查。只有你明确要求时，才运行轻量检查脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$HOME\.codex\skills\Codex-OpenCode-Worker-Workflow\scripts\check-opencode-worker.ps1" `
  -RunDir "C:\Users\you\.codex\runs\codex-opencode-worker-workflow\your-run-dir"
```

默认只读取 `worker-summary.json`、完成状态和进程状态，不读取日志尾部。确实需要看日志时再加：

```powershell
-IncludeLogTail
```

## 工作流

```mermaid
flowchart LR
  A["用户提出需求"] --> B["Codex 定向侦察"]
  B --> C["Codex 写施工任务单"]
  C --> D["Codex 后台启动 worker 并返回"]
  D --> E["OpenCode/DeepSeek 大量执行"]
  E --> F["用户按需轻量检查"]
  F --> G["用户人工查看 git diff"]
```

## 任务单格式

`AI-DEV-TASK.md` 固定包含：

- 任务目标
- Codex 定向侦察摘要
- 关键文件与入口线索
- 建议实现路线
- Worker 执行步骤
- 风险与边界
- 允许修改范围
- 禁止事项
- 验收标准
- 建议验证命令
- 交付物要求

任务单应该能指导 worker 施工：先看哪些文件、怎么定位调用链、建议怎么改、注意哪些兼容点、跑哪些验证。

## 安全边界

- 不自动 `git add/commit/push/reset`。
- 不自动创建 PR。
- 不执行发布步骤。
- `codex-worker` 允许验证命令，但显式禁止 Git 提交/推送/重置、PR、发布、危险删除和 secret 读取类命令。
- 任务单、日志和执行摘要默认保存到用户级目录，不写入业务仓库。
- API key 由 OpenCode 管理；本工具不读取、不保存、不打印。

## 手动命令

生成任务单模板：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$HOME\.codex\skills\Codex-OpenCode-Worker-Workflow\scripts\new-ai-task.ps1" `
  -RepoPath "D:\path\to\repo" `
  -Title "实现某个功能"
```

后台调用 worker。脚本现在默认后台运行，`-Background` 只是为了可读性：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$HOME\.codex\skills\Codex-OpenCode-Worker-Workflow\scripts\run-opencode-worker.ps1" `
  -RepoPath "D:\path\to\repo" `
  -TaskFile "C:\path\to\AI-DEV-TASK.md" `
  -TaskSlug "feature-name" `
  -Background
```

只有明确想让 Codex 等到 worker 完成时，才使用前台模式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$HOME\.codex\skills\Codex-OpenCode-Worker-Workflow\scripts\run-opencode-worker.ps1" `
  -RepoPath "D:\path\to\repo" `
  -TaskFile "C:\path\to\AI-DEV-TASK.md" `
  -TaskSlug "feature-name" `
  -Foreground
```

## 文件结构

```text
Codex-OpenCode-Worker-Workflow/
  SKILL.md
  README.md
  index.html
  worker.config.json
  agents/
    openai.yaml
  opencode/
    agents/
      codex-worker.md
  scripts/
    check-opencode-worker.ps1
    new-ai-task.ps1
    run-opencode-worker.ps1
```

## 常见问题

### 为什么后台运行更省 Codex？

同步等待时，Codex 会一直占着这一轮对话直到 worker 完成。后台运行后，Codex 只负责启动和报告路径，然后停止；DeepSeek/OpenCode 慢慢执行。只有你明确要求检查时，才用轻量脚本读取少量状态。

### 为什么允许 worker 运行验证命令？

因为这个 workflow 的目标是让 OpenCode/DeepSeek 承担主要 token 和执行成本。worker 可以跑测试、构建、类型检查等验证命令，但应选择与任务直接相关、耗时可控的命令。

### 为什么仍然不自动提交？

最终运行效果和业务正确性必须由用户确认。worker 可以验证，但 Git 决策仍由用户掌握。

## License

MIT
