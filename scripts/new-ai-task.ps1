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

## 当前项目背景

- 仓库路径：$root
- 项目类型：未由用户指定，worker 按需读取项目文件判断。
- 相关模块：未由用户指定，worker 按任务目标自行定位。

## 必须遵守的项目规则

- 读取并遵守当前仓库内与本任务直接相关的 AGENTS.md、README、manifest、脚本和文档同步规则。
- 只读取完成任务所需的项目上下文。
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

## 实现要求

- 按任务目标完成可审查的代码修改。
- 如果需求不明确或存在安全风险，停止并说明 blocker，不要猜测扩大范围。

## 验收标准

- 代码修改与任务目标一致。
- 用户可以通过 git diff 人工审查变更。
- 未引入明显无关改动。

## 建议验证命令

- 未由用户指定。worker 可在总结中建议命令，但本 workflow 由用户手动运行验证。

## 交付物要求

- 在当前工作区留下未提交修改，供用户人工核查、运行验证并最终确认。
"@

Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8
[pscustomobject]@{
  repo = $root
  task = $OutputPath
} | ConvertTo-Json -Depth 5
