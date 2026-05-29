param(
  [Parameter(Mandatory = $true)]
  [string]$RepoPath,

  [Parameter(Mandatory = $true)]
  [string]$Title,

  [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
  param(
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = & git -C $WorkingDirectory @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  if ($exitCode -ne 0) {
    throw "git $($Arguments -join ' ') failed: $output"
  }
  return $output
}

$repo = (Resolve-Path -LiteralPath $RepoPath).Path
$root = (Invoke-Git -WorkingDirectory $repo -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1).Trim()
$repoName = Split-Path -Leaf $root
$safeTitle = ($Title.ToLowerInvariant() -replace '[^a-z0-9\u4e00-\u9fff]+', '-').Trim('-')
if ([string]::IsNullOrWhiteSpace($safeTitle)) { $safeTitle = 'task' }

$runRoot = Join-Path $HOME '.codex\runs\codex-opencode-deepseek-workflow'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $dir = Join-Path $runRoot "$repoName-$timestamp-$safeTitle"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $OutputPath = Join-Path $dir 'AI-DEV-TASK.md'
} else {
  $parent = Split-Path -Parent $OutputPath
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
}

$content = @"
# AI 开发任务单

## 任务目标

$Title

## Codex 定向侦察摘要

- 仓库路径：$root
- Codex 已做定向侦察：未在此模板命令中填充。请由调用方补充读取过的指导文件、manifest/config、关键模块和约束。
- 如果本节为空，worker 应自行读取项目指导文件、manifest/config 和与任务目标相关的模块。

## 关键文件与入口线索

- 优先读取当前仓库内与任务直接相关的 AGENTS.md、README、manifest、脚本和文档同步规则。
- 使用 grep/glob/search 定位与任务目标相关的入口、调用链、测试和配置。
- 不要假设本任务单列出的线索完整；以仓库实际代码为准。

## 建议实现路线

- 先确认项目约定、相关入口和现有实现模式。
- 沿调用链定位最小必要修改点。
- 按现有风格实现，避免大范围重构、格式化或无关依赖变更。
- 修改后运行合适的验证命令，并在总结中说明结果。

## Worker 执行步骤

- 补充读取完成任务所需的上下文，允许大量使用 OpenCode/DeepSeek token。
- 根据建议路线实现代码修改，但如果仓库事实与建议路线冲突，以仓库事实为准。
- 只运行与本任务直接相关、耗时可控的验证命令。
- 如果需求不明确、验证无法运行或存在安全风险，停止并说明 blocker，不要猜测扩大范围。

## 风险与边界

- 保留已有用户改动。
- 不修改与任务无关的文件。
- 不引入无关重构、迁移或发布流程。

## 必须遵守的项目规则

- 读取并遵守当前仓库内与本任务直接相关的 AGENTS.md、README、manifest、脚本和文档同步规则。
- 优先做最小必要修改，不做无关重构。
- 不修改与任务无关的文件；保留已有用户改动。

## 允许修改范围

- 仅限实现任务目标所必需的文件。

## 禁止事项

- 不运行 git add / commit / merge / push / reset。
- 不创建 PR。
- 不重写未授权的用户文件。
- 不做超出任务范围的重构。
- 不读取、输出或保存 API Key。
- 不新增大范围格式化、迁移或依赖变更，除非任务目标必须要求。
- 不执行发布步骤，不创建 PR。

## 验收标准

- 代码修改与任务目标一致。
- 用户可以通过 git diff 人工审查变更。
- 未引入明显无关改动。
- worker 简要列出已运行的验证命令及其结果；如果失败，说明失败原因和后续建议。

## 建议验证命令

- 未由用户指定。worker 应根据项目 manifest、脚本和文档选择聚焦且耗时可控的验证命令运行。

## 交付物要求

- 在当前工作区留下未提交修改，供用户人工核查并最终确认。
- 在 worker 简短总结中列出修改内容、验证命令、验证结果、未完成事项或 blocker。
"@

Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8
[pscustomobject]@{
  repo = $root
  task = $OutputPath
} | ConvertTo-Json -Depth 5
