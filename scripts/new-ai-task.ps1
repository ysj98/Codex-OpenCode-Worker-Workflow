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
# AI Development Task Order

> Codex should replace the English helper labels below with the required task
> order section titles from the skill instructions before handing the task order
> to OpenCode.

## Task Goal

$Title

## Current Project Context

- Repository path: $root
- Project type:
- Related modules:

## Required Project Rules

- Read and follow this repository's AGENTS.md, README, manifests, and documentation sync rules.
- Do not modify files unrelated to the task.

## Allowed Write Scope

- 

## Forbidden Actions

- Do not run git add / commit / merge / push / reset.
- Do not create pull requests.
- Do not rewrite unauthorized user files.
- Do not do out-of-scope refactors.

## Implementation Requirements

- 

## Acceptance Criteria

- 

## Suggested Verification Commands

- 

## Deliverables

- Leave an unstaged diff for Codex review and final user confirmation.
"@

Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8
[pscustomobject]@{
  repo = $root
  task = $OutputPath
} | ConvertTo-Json -Depth 5
