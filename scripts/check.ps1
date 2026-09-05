# Headless import, behavior checks, and entry-scene smoke check.
[CmdletBinding()]
param([string]$GodotPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$enginePath = & (Join-Path $PSScriptRoot 'godot.ps1') -GodotPath $GodotPath -ResolveOnly
$artifactPath = Join-Path $projectRoot '.artifacts/checks'
[System.IO.Directory]::CreateDirectory($artifactPath) | Out-Null

function Invoke-GodotCheck {
    param(
        [string]$Name,
        [string[]]$EngineArguments,
        [string]$RequiredOutput = ''
    )
    $stdoutPath = Join-Path $artifactPath ($Name + '.stdout.log')
    $stderrPath = Join-Path $artifactPath ($Name + '.stderr.log')
    $logPath = Join-Path $artifactPath ($Name + '.godot.log')
    # Arguments below are fixed switches or quoted absolute project paths.
    $arguments = @('--headless', '--path', ('"' + $projectRoot + '"'),
        '--log-file', ('"' + $logPath + '"')) + $EngineArguments
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo.FileName = $enginePath
    $process.StartInfo.Arguments = $arguments -join ' '
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.Start() | Out-Null
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        $process.WaitForExit()
        throw "$Name timed out after 60 seconds. Logs: $artifactPath"
    }
    # Ensure redirected output is flushed before reading it.
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [System.IO.File]::WriteAllText($stdoutPath, $stdout)
    [System.IO.File]::WriteAllText($stderrPath, $stderr)
    $output = $stdout + [Environment]::NewLine + $stderr
    if ($output.Trim()) {
        Write-Host $output.Trim()
    }
    if ($process.ExitCode -ne 0) {
        throw "$Name failed with exit code $($process.ExitCode). Logs: $artifactPath"
    }
    if ($output -match '(?m)^\s*(SCRIPT ERROR:|ERROR:|FAIL:)') {
        throw "$Name reported an error. Logs: $artifactPath"
    }
    if ($RequiredOutput -and $output -notmatch [Regex]::Escape($RequiredOutput)) {
        throw "$Name did not report completion. Logs: $artifactPath"
    }
    Write-Host "[PASS] $Name"
}

Push-Location $projectRoot
try {
    Invoke-GodotCheck -Name 'import' -EngineArguments @('--editor', '--import')
    Invoke-GodotCheck -Name 'behavior' -EngineArguments @('--script', 'res://tests/run_tests.gd') -RequiredOutput 'CHECKS PASSED:'
    Invoke-GodotCheck -Name 'entry' -EngineArguments @('--quit-after', '3')
    Write-Host 'All scaffold checks passed.'
} finally {
    Pop-Location
}
