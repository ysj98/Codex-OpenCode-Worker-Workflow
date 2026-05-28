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
- 项目类型：
- 相关模块：

## 必须遵守的项目规则

- 读取并遵守当前仓库的 AGENTS.md、README、manifest、脚本和文档同步规则。
- 不修改与任务无关的文件。

## 允许修改范围

- 

## 禁止事项

- 不运行 git add / commit / merge / push / reset。
- 不创建 PR。
- 不重写未授权的用户文件。
- 不做超出任务范围的重构。
- 不读取、输出或保存 API Key。

## 实现要求

- 

## 验收标准

- 

## 建议验证命令

- 

## 交付物要求

- 在隔离 worktree 中留下未暂存 diff，供 Codex 审查和用户最终确认。
"@

Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8
[pscustomobject]@{
  repo = $root
  task = $OutputPath
} | ConvertTo-Json -Depth 5
