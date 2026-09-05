# Usage: .\scripts\godot.ps1 -GodotArgs '--editor'
[CmdletBinding()]
param(
    [string]$GodotPath,
    [string[]]$GodotArgs = @(),
    [switch]$ResolveOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$enginePath = $null

if ($GodotPath) {
    $enginePath = (Resolve-Path -LiteralPath $GodotPath).Path
} elseif ($env:GODOT_BIN) {
    $enginePath = (Resolve-Path -LiteralPath $env:GODOT_BIN).Path
} else {
    $parentPath = Split-Path -Parent $projectRoot
    $candidates = @(Get-ChildItem -LiteralPath $parentPath -Filter 'Godot_v4.6.1-stable_win64.exe' -File)
    if ($candidates.Count -gt 0) {
        $enginePath = $candidates[0].FullName
    } else {
        $engineCommand = Get-Command godot -ErrorAction SilentlyContinue
        if ($engineCommand) {
            $enginePath = $engineCommand.Source
        }
    }
}

if (-not $enginePath -or -not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw 'Godot not found. Pass -GodotPath or set GODOT_BIN. Expected version: 4.6.1.'
}
if ($ResolveOnly) {
    return $enginePath
}

function Invoke-Engine {
    param([string[]]$EngineArguments, [int]$TimeoutSeconds = 0)
    # Quote Windows native arguments, including spaces, quotes and trailing slashes.
    $quotedArguments = foreach ($argument in $EngineArguments) {
        '"' + [Regex]::Replace([Regex]::Replace($argument, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo.FileName = $enginePath
    $process.StartInfo.Arguments = $quotedArguments -join ' '
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.Start() | Out-Null
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if ($TimeoutSeconds -gt 0 -and -not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill()
        $process.WaitForExit()
        throw "Godot timed out after $TimeoutSeconds seconds."
    }
    $process.WaitForExit()
    $result = @{
        ExitCode = $process.ExitCode
        Output = $stdoutTask.GetAwaiter().GetResult() + [Environment]::NewLine + $stderrTask.GetAwaiter().GetResult()
    }
    $process.Dispose()
    return $result
}

$classCache = Join-Path $projectRoot '.godot/global_script_class_cache.cfg'
if (-not (Test-Path -LiteralPath $classCache)) {
    Write-Host 'First launch: importing Godot resources and script classes...'
    $importResult = Invoke-Engine -EngineArguments @('--headless', '--path', $projectRoot, '--editor', '--import') -TimeoutSeconds 60
    Write-Host $importResult.Output.Trim()
    if ($importResult.ExitCode -ne 0 -or $importResult.Output -match '(?m)^\s*(SCRIPT ERROR:|ERROR:)') {
        throw 'First-launch import failed. Run scripts/check.ps1 for details.'
    }
}

$runResult = Invoke-Engine -EngineArguments (@('--path', $projectRoot) + $GodotArgs)
if ($runResult.Output.Trim()) {
    Write-Host $runResult.Output.Trim()
}
if ($runResult.Output -match '(?m)^\s*(SCRIPT ERROR:|ERROR:)') {
    exit 1
}
exit $runResult.ExitCode
