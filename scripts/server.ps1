# 用法：.\scripts\server.ps1 [-GodotPath '<godot.exe>'] [-Port 27840] [-SingleCat]
[CmdletBinding()]
param(
    [string]$GodotPath,
    [ValidateRange(1, 65535)]
    [int]$Port = 27840,
    [switch]$SingleCat
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$enginePath = & (Join-Path $PSScriptRoot 'godot.ps1') -GodotPath $GodotPath -ResolveOnly
$serverEntry = Join-Path $projectRoot 'src/network/server_main.gd'
if (-not (Test-Path -LiteralPath $serverEntry -PathType Leaf)) {
    throw "Server entry not found: $serverEntry"
}

# 每次启动独立保留日志，既不覆盖证据，也不接管已有服务器进程。
$launchId = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$artifactPath = Join-Path $projectRoot ('.artifacts/server/' + $launchId)
[System.IO.Directory]::CreateDirectory($artifactPath) | Out-Null
$godotLogPath = Join-Path $artifactPath 'server.godot.log'
$stdoutPath = Join-Path $artifactPath 'server.stdout.log'
$stderrPath = Join-Path $artifactPath 'server.stderr.log'

$engineArguments = @(
    '--headless', '--path', $projectRoot,
    '--log-file', $godotLogPath,
    '--script', 'res://src/network/server_main.gd',
    '--', "--port=$Port"
)
$mode = 'three-players'
if ($SingleCat) {
    $engineArguments += '--single-cat'
    $mode = 'single-cat-debug'
}

# Start-Process 会拼接参数；逐项按 Windows 原生命令行规则转义，兼容空格和尾部反斜杠。
$quotedArguments = foreach ($argument in $engineArguments) {
    '"' + [Regex]::Replace([Regex]::Replace($argument, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
$serverProcess = Start-Process -FilePath $enginePath -ArgumentList ($quotedArguments -join ' ') `
    -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

try {
    # 捕获立即退出的端口冲突或脚本错误；存活检查不代表网络协议已经完成验收。
    if ($serverProcess.WaitForExit(1500)) {
        $serverProcess.WaitForExit()
        $exitCode = $serverProcess.ExitCode
        $failureOutput = foreach ($logFile in @($godotLogPath, $stderrPath, $stdoutPath)) {
            if (Test-Path -LiteralPath $logFile -PathType Leaf) {
                Get-Content -LiteralPath $logFile -Tail 12
            }
        }
        $details = ($failureOutput -join [Environment]::NewLine).Trim()
        throw "Server exited during startup (PID $($serverProcess.Id), port $Port, exit code $exitCode). Logs: $artifactPath$([Environment]::NewLine)$details"
    }

    [PSCustomObject]@{
        PID = $serverProcess.Id
        Port = $Port
        Mode = $mode
        EnginePath = $enginePath
        ProjectPath = $projectRoot
        GodotLog = $godotLogPath
        StdoutLog = $stdoutPath
        StderrLog = $stderrPath
        StartupCheck = 'Process remained alive for 1500 ms; network readiness not verified.'
    }
} finally {
    # 只释放启动器的句柄；后台服务器继续运行，不停止任何已有或新建服务。
    $serverProcess.Dispose()
}
