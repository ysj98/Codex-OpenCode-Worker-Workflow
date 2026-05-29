param(
  [Parameter(Mandatory = $true)]
  [string]$RunDir,

  [int]$TailLines = 8,
  [int]$MaxTailChars = 3000,
  [switch]$IncludeLogTail,
  [switch]$NoLogTail
)

$ErrorActionPreference = 'Stop'

function Get-FileTail {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$Lines,
    [int]$MaxChars
  )

  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  $tail = @(Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction SilentlyContinue)
  if ($tail.Count -eq 0) { return @() }

  $text = $tail -join [Environment]::NewLine
  if ($text.Length -gt $MaxChars) {
    $text = $text.Substring($text.Length - $MaxChars)
  }
  return @($text -split [Environment]::NewLine)
}

$resolvedRunDir = (Resolve-Path -LiteralPath $RunDir).Path
$summaryPath = Join-Path $resolvedRunDir 'worker-summary.json'
if (-not (Test-Path -LiteralPath $summaryPath)) {
  throw "worker-summary.json was not found in $resolvedRunDir"
}

$summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
$completion = $null
if ($summary.completionFile -and (Test-Path -LiteralPath $summary.completionFile)) {
  $completion = Get-Content -Raw -LiteralPath $summary.completionFile | ConvertFrom-Json
}

$isRunning = $false
if ($null -ne $summary.processId -and -not [string]::IsNullOrWhiteSpace([string]$summary.processId)) {
  $process = Get-Process -Id ([int]$summary.processId) -ErrorAction SilentlyContinue
  $isRunning = $null -ne $process
}

$status = $summary.status
$exitCode = $summary.opencodeExitCode
if ($completion) {
  $status = $completion.status
  $exitCode = $completion.opencodeExitCode
} elseif ($summary.prepareOnly) {
  $status = 'prepared'
} elseif ($summary.background -and $isRunning) {
  $status = 'running'
} elseif ($summary.background) {
  $status = 'exited-without-completion-file'
}

$logTail = @()
if ($IncludeLogTail -and -not $NoLogTail -and $summary.opencodeLog) {
  $logTail = Get-FileTail -Path $summary.opencodeLog -Lines $TailLines -MaxChars $MaxTailChars
}

$stderrTail = @()
if ($IncludeLogTail -and -not $NoLogTail -and $summary.opencodeStderr) {
  $stderrTail = Get-FileTail -Path $summary.opencodeStderr -Lines 8 -MaxChars 3000
}

[pscustomobject]@{
  taskId = $summary.taskId
  status = $status
  processId = $summary.processId
  processRunning = $isRunning
  opencodeExitCode = $exitCode
  targetRepo = $summary.targetRepo
  runDir = $summary.runDir
  taskFile = $summary.taskFile
  opencodeLog = $summary.opencodeLog
  opencodeStderr = $summary.opencodeStderr
  completionFile = $summary.completionFile
  logTailIncluded = [bool]($IncludeLogTail -and -not $NoLogTail)
  logTailLines = if ($IncludeLogTail -and -not $NoLogTail) { $TailLines } else { 0 }
  logTail = $logTail
  stderrTail = $stderrTail
} | ConvertTo-Json -Depth 8
