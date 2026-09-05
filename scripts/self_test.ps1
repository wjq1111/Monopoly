# 完整 M0 自测；退出 2 表示自动用例通过、视觉审阅仍待执行。
[CmdletBinding()]
param(
    [string]$GodotPath,
    [string]$PythonPath,
    [switch]$RecordMovie,
    [string]$WindowPosition = '80,80'
)
$ErrorActionPreference = 'Stop'
$enginePath = & (Join-Path $PSScriptRoot 'godot.ps1') -GodotPath $GodotPath -ResolveOnly
if (-not $PythonPath) { $PythonPath = (Get-Command python -ErrorAction Stop).Source }
$runnerArguments = @((Join-Path $PSScriptRoot 'self_test.py'), 'run', '--godot', $enginePath, "--position=$WindowPosition")
if ($RecordMovie) { $runnerArguments += '--record-movie' }
& $PythonPath @runnerArguments
exit $LASTEXITCODE
