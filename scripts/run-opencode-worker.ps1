param(
  [Parameter(Mandatory = $true)]
  [string]$RepoPath,

  [Parameter(Mandatory = $true)]
  [string]$TaskFile,

  [string]$FindingsFile,
  [string]$ExistingWorktreePath,
  [string]$SessionId,
  [string]$TaskSlug,
  [string]$ModelProfile,
  [string]$Model,
  [string]$Agent,
  [string]$RunsRoot,
  [string]$WorktreesRoot,
  [switch]$PrepareOnly,
  [switch]$AutoApproveOpenCodePermissions
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

function ConvertTo-Slug {
  param([string]$Value)
  $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
  if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'task' }
  if ($slug.Length -gt 48) { $slug = $slug.Substring(0, 48).Trim('-') }
  return $slug
}

function Get-JsonField {
  param($Object, [string]$Name, [string]$Default)
  if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name -and -not [string]::IsNullOrWhiteSpace([string]$Object.$Name)) {
    return [string]$Object.$Name
  }
  return $Default
}

function Get-JsonObjectField {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-ModelFromProfile {
  param($Config, [string]$Name, [string]$ConfigPath)
  $profiles = Get-JsonObjectField -Object $Config -Name 'modelProfiles'
  if ($null -eq $profiles) {
    throw "Model profile '$Name' was requested, but worker.config.json does not define modelProfiles."
  }

  $profile = Get-JsonObjectField -Object $profiles -Name $Name
  if ($null -eq $profile) {
    $available = @($profiles.PSObject.Properties.Name) -join ', '
    if ([string]::IsNullOrWhiteSpace($available)) { $available = '(none)' }
    throw "Model profile '$Name' was not found in $ConfigPath. Available profiles: $available"
  }

  $profileModel = Get-JsonField -Object $profile -Name 'model' -Default ''
  if ([string]::IsNullOrWhiteSpace($profileModel)) {
    throw "Model profile '$Name' in $ConfigPath does not define a model."
  }
  return $profileModel
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = Resolve-Path -LiteralPath (Join-Path $scriptRoot '..')
$configPath = Join-Path $skillRoot.Path 'worker.config.json'
$config = $null
if (Test-Path -LiteralPath $configPath) {
  $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
}

if ([string]::IsNullOrWhiteSpace($Model)) {
  $Model = [Environment]::GetEnvironmentVariable('CODEX_OPENCODE_MODEL')
}

$resolvedModelProfile = $null
if ([string]::IsNullOrWhiteSpace($Model)) {
  if ([string]::IsNullOrWhiteSpace($ModelProfile)) {
    $ModelProfile = [Environment]::GetEnvironmentVariable('CODEX_OPENCODE_MODEL_PROFILE')
  }
  if ([string]::IsNullOrWhiteSpace($ModelProfile)) {
    $ModelProfile = Get-JsonField -Object $config -Name 'defaultModelProfile' -Default ''
  }
  if (-not [string]::IsNullOrWhiteSpace($ModelProfile)) {
    $Model = Get-ModelFromProfile -Config $config -Name $ModelProfile -ConfigPath $configPath
    $resolvedModelProfile = $ModelProfile
  }
}

if ([string]::IsNullOrWhiteSpace($Model)) {
  throw "No OpenCode model configured. Pass -Model, set CODEX_OPENCODE_MODEL, pass -ModelProfile, set CODEX_OPENCODE_MODEL_PROFILE, or configure defaultModelProfile in worker.config.json."
}
if ([string]::IsNullOrWhiteSpace($Agent)) { $Agent = Get-JsonField -Object $config -Name 'agent' -Default 'codex-worker' }
if ([string]::IsNullOrWhiteSpace($RunsRoot)) { $RunsRoot = Get-JsonField -Object $config -Name 'runsRoot' -Default (Join-Path $HOME '.codex\runs\codex-opencode-deepseek-workflow') }
if ([string]::IsNullOrWhiteSpace($WorktreesRoot)) { $WorktreesRoot = Get-JsonField -Object $config -Name 'worktreesRoot' -Default (Join-Path $HOME '.codex\worktrees') }

$repoInput = (Resolve-Path -LiteralPath $RepoPath).Path
$taskSource = (Resolve-Path -LiteralPath $TaskFile).Path
$sourceRoot = (Invoke-Git -WorkingDirectory $repoInput -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1).Trim()
$sourceStatus = Invoke-Git -WorkingDirectory $sourceRoot -Arguments @('status', '--porcelain=v1')

if (-not $ExistingWorktreePath -and $sourceStatus.Count -gt 0) {
  throw "Source worktree is not clean. Commit, stash, or discard local changes before delegating to OpenCode."
}

$repoName = ConvertTo-Slug (Split-Path -Leaf $sourceRoot)
if ([string]::IsNullOrWhiteSpace($TaskSlug)) {
  $TaskSlug = ConvertTo-Slug ([IO.Path]::GetFileNameWithoutExtension($taskSource))
} else {
  $TaskSlug = ConvertTo-Slug $TaskSlug
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$taskId = "$timestamp-$TaskSlug"
$runDir = Join-Path $RunsRoot "$repoName-$taskId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

if ($ExistingWorktreePath) {
  $worktree = (Resolve-Path -LiteralPath $ExistingWorktreePath).Path
  $worktreeRoot = (Invoke-Git -WorkingDirectory $worktree -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1).Trim()
  $worktree = $worktreeRoot
  $branch = (Invoke-Git -WorkingDirectory $worktree -Arguments @('branch', '--show-current') | Select-Object -First 1).Trim()
} else {
  New-Item -ItemType Directory -Force -Path $WorktreesRoot | Out-Null
  $worktree = Join-Path $WorktreesRoot "$repoName-$taskId"
  if (Test-Path -LiteralPath $worktree) {
    throw "Worktree path already exists: $worktree"
  }
  $branch = "codex/opencode-$taskId"
  Invoke-Git -WorkingDirectory $sourceRoot -Arguments @('worktree', 'add', '-b', $branch, $worktree, 'HEAD') | Out-Null
}

$taskCopy = Join-Path $runDir 'AI-DEV-TASK.md'
Copy-Item -LiteralPath $taskSource -Destination $taskCopy -Force

$findingsCopy = $null
if ($FindingsFile) {
  $findingsSource = (Resolve-Path -LiteralPath $FindingsFile).Path
  $findingsCopy = Join-Path $runDir 'CODEX-REVIEW-FINDINGS.md'
  Copy-Item -LiteralPath $findingsSource -Destination $findingsCopy -Force
}

$prompt = @"
You are the implementation worker using the configured OpenCode model in a Codex-controlled workflow.

Use the attached AI development task order as the complete implementation contract.
Modify code only in the current worktree.
Do not stage, commit, merge, push, create branches, create PRs, or run release steps.
Do not use shell commands; Codex will run verification after your changes.

If CODEX-REVIEW-FINDINGS.md is attached, repair only the required findings.
"@

$logPath = Join-Path $runDir 'opencode-events.jsonl'
$summaryPath = Join-Path $runDir 'worker-summary.json'

$exitCode = 0
if (-not $PrepareOnly) {
  $opencode = Get-Command opencode -ErrorAction Stop
  $args = @(
    'run',
    '--dir', $worktree,
    '--agent', $Agent,
    '--model', $Model,
    '--format', 'json',
    '--title', "Codex OpenCode $taskId",
    '--file', $taskCopy
  )
  if ($findingsCopy) { $args += @('--file', $findingsCopy) }
  if ($SessionId) { $args += @('--session', $SessionId) }
  if ($AutoApproveOpenCodePermissions) { $args += '--dangerously-skip-permissions' }
  $args += $prompt

  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $opencodeOutput = & $opencode.Source @args 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  $opencodeOutput | Set-Content -LiteralPath $logPath -Encoding UTF8
} else {
  Set-Content -LiteralPath $logPath -Value '{"prepareOnly":true}' -Encoding UTF8
}

$diffStat = Invoke-Git -WorkingDirectory $worktree -Arguments @('diff', '--stat')
$status = Invoke-Git -WorkingDirectory $worktree -Arguments @('status', '--short')

$summary = [pscustomobject]@{
  taskId = $taskId
  sourceRepo = $sourceRoot
  worktree = $worktree
  branch = $branch
  runDir = $runDir
  taskFile = $taskCopy
  findingsFile = $findingsCopy
  modelProfile = $resolvedModelProfile
  model = $Model
  agent = $Agent
  prepareOnly = [bool]$PrepareOnly
  autoApproveOpenCodePermissions = [bool]$AutoApproveOpenCodePermissions
  opencodeExitCode = $exitCode
  opencodeLog = $logPath
  gitStatus = @($status)
  gitDiffStat = @($diffStat)
  nextSteps = @(
    'Codex reviews git diff in the generated worktree.',
    'Codex runs project verification commands in the generated worktree.',
    'User runs the project and commits manually only after confirmation.'
  )
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8

if ($exitCode -ne 0) {
  throw "opencode run failed with exit code $exitCode. See $logPath"
}
