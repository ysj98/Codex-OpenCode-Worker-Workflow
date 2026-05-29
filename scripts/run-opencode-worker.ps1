param(
  [Parameter(Mandatory = $true)]
  [string]$RepoPath,

  [Parameter(Mandatory = $true)]
  [string]$TaskFile,

  [string]$SessionId,
  [string]$TaskSlug,
  [string]$ModelProfile,
  [string]$Model,
  [string]$Agent,
  [string]$RunsRoot,
  [switch]$PrepareOnly
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

$repoInput = (Resolve-Path -LiteralPath $RepoPath).Path
$taskSource = (Resolve-Path -LiteralPath $TaskFile).Path
$targetRootRaw = (Invoke-Git -WorkingDirectory $repoInput -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1).Trim()
$targetRoot = (Resolve-Path -LiteralPath $targetRootRaw).Path

$repoName = ConvertTo-Slug (Split-Path -Leaf $targetRoot)
if ([string]::IsNullOrWhiteSpace($TaskSlug)) {
  $TaskSlug = ConvertTo-Slug ([IO.Path]::GetFileNameWithoutExtension($taskSource))
} else {
  $TaskSlug = ConvertTo-Slug $TaskSlug
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$taskId = "$timestamp-$TaskSlug"
$runDir = Join-Path $RunsRoot "$repoName-$taskId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$taskCopy = Join-Path $runDir 'AI-DEV-TASK.md'
Copy-Item -LiteralPath $taskSource -Destination $taskCopy -Force

$prompt = @"
You are the implementation and verification worker using the configured OpenCode model in a low-Codex-consumption workflow.

Use the attached AI development task order as the implementation contract and starting plan.
Codex has intentionally performed only bounded targeted reconnaissance to save its own tokens.
You may spend substantial worker-model tokens reading project files, searching, tracing call paths, implementing, and running validation commands.

Follow the task order's suggested route, but verify every assumption against the repository before changing code.
Modify code only in the current Git working directory.
Run appropriate tests, builds, type checks, linters, or focused validation commands when available.
Do not stage, commit, merge, push, create branches, create pull requests, or run release steps.
Do not read, print, or store secrets or API keys.

If the task order is ambiguous, contradicted by the repository, or unsafe, stop and explain the blocker instead of guessing.
In your final response, summarize changed files, validation commands and results, remaining risks, and any blocker.
"@

$logPath = Join-Path $runDir 'opencode-events.jsonl'
$summaryPath = Join-Path $runDir 'worker-summary.json'

$exitCode = 0
if (-not $PrepareOnly) {
  $opencode = Get-Command opencode -ErrorAction Stop
  $args = @(
    'run',
    $prompt,
    '--dir', $targetRoot,
    '--agent', $Agent,
    '--model', $Model,
    '--format', 'json',
    '--title', "Codex OpenCode $taskId",
    '--file', $taskCopy
  )
  if ($SessionId) { $args += @('--session', $SessionId) }

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

$summary = [pscustomobject]@{
  taskId = $taskId
  targetRepo = $targetRoot
  workingDirectory = $targetRoot
  runDir = $runDir
  taskFile = $taskCopy
  modelProfile = $resolvedModelProfile
  model = $Model
  agent = $Agent
  prepareOnly = [bool]$PrepareOnly
  opencodeExitCode = $exitCode
  opencodeLog = $logPath
  nextSteps = @(
    'User reviews git diff in the current working directory.',
    'User reviews the worker validation summary and may rerun verification manually.',
    'User commits manually only after confirming the result.',
    'Codex does not perform final diff review, business validation, or Git finalization in this workflow.'
  )
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8

if ($exitCode -ne 0) {
  throw "opencode run failed with exit code $exitCode. See $logPath"
}
