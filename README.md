# Codex OpenCode Worker Workflow

一个本地个人级 Codex skill。它的唯一目标是：尽可能减少 Codex 的 token/费用消耗，同时利用 Codex 的任务拆解与安全边界能力，把实际读仓库和改代码的高消耗工作交给 OpenCode worker，例如 DeepSeek。

默认模型 profile 是 DeepSeek V4 Pro，但 `codex-worker` 本身不绑定模型。以后切换到其他 OpenCode 模型时，只改 `worker.config.json` 或脚本参数即可，不需要改 agent。

仓库地址：[ysj98/codex-opencode-deepseek-workflow](https://github.com/ysj98/codex-opencode-deepseek-workflow)

## 它解决什么问题

传统 Codex 实现任务通常会消耗在这些环节：

- 读取大量项目上下文
- 推断架构和实现细节
- 修改代码
- 复核 diff
- 运行验证并修复

这个 workflow 刻意把 Codex 压缩成一个轻量调度器：

- **Codex**：只生成短任务单、启动 OpenCode、报告结果和日志位置。
- **OpenCode worker 模型**：读取它需要的项目上下文，并在当前 Git 工作区改代码。
- **用户**：人工查看 `git diff`、运行项目/测试、确认 UI 或业务效果，并决定是否 `git add/commit/push`。

它不会让 Codex 复核 diff、不会自动二次修复、不会自动提交 Git。这样能明显降低 Codex 消耗，但也意味着人工核查是必需步骤。

## 快速开始

### 1. 安装 skill

```powershell
git clone https://github.com/ysj98/codex-opencode-deepseek-workflow.git `
  "$HOME\.codex\skills\codex-opencode-deepseek-workflow"
```

### 2. 安装 OpenCode worker agent

```powershell
New-Item -ItemType Directory -Force "$HOME\.config\opencode\agents" | Out-Null

Copy-Item `
  "$HOME\.codex\skills\codex-opencode-deepseek-workflow\opencode\agents\codex-worker.md" `
  "$HOME\.config\opencode\agents\codex-worker.md" `
  -Force
```

`codex-worker` 只是一个可选 agent。只有脚本显式调用 `opencode run --agent codex-worker`，或你在 OpenCode 界面主动选择它时，它才会生效。

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
使用 $codex-opencode-deepseek-workflow，帮我实现这个需求：
...
```

或者：

```text
用 OpenCode + DeepSeek 执行，Codex 只负责写任务单和启动 worker：
...
```

Codex 会生成轻量 `AI-DEV-TASK.md`，再调用 OpenCode worker 在当前工作区留下未提交修改。之后由你人工核查 `git diff`、运行项目和测试。

## 工作流

```mermaid
flowchart LR
  A["用户提出需求"] --> B["Codex 写轻量任务单"]
  B --> C["Codex 启动 OpenCode worker"]
  C --> D["Worker 读取项目并改代码"]
  D --> E["用户人工查看 git diff"]
  E --> F["用户运行验证"]
  F --> G["用户决定 Git 操作"]
```

## Codex 低消耗原则

- Codex 不做大范围项目分析。
- Codex 不预先替 worker 设计完整实现。
- Codex 不跑 `git diff`、测试、构建、浏览器检查或修复循环。
- Codex 只写目标、边界、禁止事项、验收标准和已知验证建议。
- 任务单尽量短，通常不超过 120 行。
- 如果 worker 失败，Codex 只报告日志和退出码，不自动重试。

## 模型配置

模型解析优先级：

1. `-Model`
2. `CODEX_OPENCODE_MODEL`
3. `-ModelProfile`
4. `CODEX_OPENCODE_MODEL_PROFILE`
5. `worker.config.json` 的 `defaultModelProfile`

默认配置：

```json
{
  "defaultModelProfile": "deepseek-v4-pro",
  "modelProfiles": {
    "deepseek-v4-pro": {
      "model": "deepseek/deepseek-v4-pro"
    }
  },
  "agent": "codex-worker",
  "runsRoot": ""
}
```

切换到其他模型时，新增 profile 并修改 `defaultModelProfile`：

```json
{
  "defaultModelProfile": "my-model",
  "modelProfiles": {
    "deepseek-v4-pro": {
      "model": "deepseek/deepseek-v4-pro"
    },
    "my-model": {
      "model": "provider/model-id"
    }
  }
}
```

也可以临时覆盖：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$HOME\.codex\skills\codex-opencode-deepseek-workflow\scripts\run-opencode-worker.ps1" `
  -RepoPath "D:\path\to\repo" `
  -TaskFile "C:\path\to\AI-DEV-TASK.md" `
  -Model "provider/model-id"
```

## 任务单格式

`AI-DEV-TASK.md` 固定包含：

- 任务目标
- 当前项目背景
- 必须遵守的项目规则
- 允许修改范围
- 禁止事项
- 实现要求
- 验收标准
- 建议验证命令
- 交付物要求

任务单应该尽量短，只写目标、边界、禁止事项和已知验证方式。不要把 Codex 的长分析塞进任务单。

## 安全边界

- 不自动 `git add`、`commit`、`push`。
- 不自动创建 PR。
- 不使用 OpenCode 自动权限批准或危险权限跳过模式。
- `codex-worker` 禁止 shell、子任务、外部目录、提交、推送和建 PR。
- 任务单、日志和执行摘要默认保存到用户级目录，不写入业务仓库。
- API key 由 OpenCode 管理；本工具不读取、不保存、不打印。
- 当前工作区已有修改时不会阻断；你需要自行区分旧 diff 和 worker 新 diff。

## 手动命令

生成任务单模板：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$HOME\.codex\skills\codex-opencode-deepseek-workflow\scripts\new-ai-task.ps1" `
  -RepoPath "D:\path\to\repo" `
  -Title "实现某个功能"
```

调用 worker：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$HOME\.codex\skills\codex-opencode-deepseek-workflow\scripts\run-opencode-worker.ps1" `
  -RepoPath "D:\path\to\repo" `
  -TaskFile "C:\path\to\AI-DEV-TASK.md" `
  -TaskSlug "feature-name"
```

## 文件结构

```text
codex-opencode-deepseek-workflow/
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
    new-ai-task.ps1
    run-opencode-worker.ps1
```

## 常见问题

### codex-worker 会改变我的默认 OpenCode 行为吗？

不会。它只是一个可选 agent，不会修改你的供应商连接、API key、默认模型或默认 agent。

### 为什么不要求工作区干净？

这是为了减少流程和 token 消耗，让 OpenCode 直接在当前工作区执行。代价是已有修改和 worker 修改会出现在同一个 diff 里，需要你人工核查。

### 为什么不自动验收？

这个 skill 的目标是降低 Codex 消耗，而不是替代完整工程闭环。最终运行效果和业务正确性必须由用户确认。

## License

MIT
