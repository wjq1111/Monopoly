# 仅在实际查看本次截图后记录审阅；不会自动判断画面是否合格。
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][ValidateSet('PASSED','FAILED','BLOCKED')][string]$Status,
    [Parameter(Mandatory=$true)][string]$Reviewer,
    [Parameter(Mandatory=$true)][string]$Notes,
    [Parameter(Mandatory=$true)][string]$Evidence,
    [string]$PythonPath
)
$ErrorActionPreference = 'Stop'
if (-not $PythonPath) { $PythonPath = (Get-Command python -ErrorAction Stop).Source }
$runnerArguments = @((Join-Path $PSScriptRoot 'self_test.py'), 'review', '--run-id', $RunId, '--status', $Status, '--reviewer', $Reviewer, '--notes', $Notes)
foreach ($item in $Evidence.Split(',')) {
    if ($item.Trim()) { $runnerArguments += @('--evidence', $item.Trim()) }
}
& $PythonPath @runnerArguments
exit $LASTEXITCODE
