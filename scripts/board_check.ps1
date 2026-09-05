# 棋盘需求验收：默认功能与稳定性检查；主动尺寸轮转须显式开启。
[CmdletBinding()]
param(
    [string]$GodotPath,
    [switch]$StabilityOnly,
    [switch]$ResolutionSweep
)
$ErrorActionPreference = 'Stop'
if ($StabilityOnly -and $ResolutionSweep) {
    throw '-StabilityOnly 只检查稳定性，不能同时指定 -ResolutionSweep。需扫尺寸时单独使用 -ResolutionSweep。'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$enginePath = & (Join-Path $PSScriptRoot 'godot.ps1') -GodotPath $GodotPath -ResolveOnly
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$evidencePath = Join-Path $projectRoot ('.artifacts/board-interface/' + $runId)
[IO.Directory]::CreateDirectory($evidencePath) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$sourcePaths = @('project.godot','tests/test_board_interface.gd','tests/test_resolution_stability.gd','tests/test_room_network.gd','tests/test_report.gd','tests/run_tests.gd','data/rules/default_rules.tres',
    'docs/testing/需求追踪矩阵.md','docs/testing/策划测试用例.md','docs/故事审阅与开工前条件.md','scripts/board_check.ps1')
foreach ($sourceFolder in @('src/app','src/ui','src/network','src/domain','assets/art/cats','assets/art/tiles')) {
    $sourcePaths += Get-ChildItem -LiteralPath (Join-Path $projectRoot $sourceFolder) -File |
        Where-Object { $_.Extension -notin @('.import','.uid') } |
        ForEach-Object { $_.FullName.Substring($projectRoot.Length + 1).Replace('\','/') }
}
$manifest = [ordered]@{
    run_id=$runId
    scope=$(if ($StabilityOnly) {'TC-BOARD-010 窗口与棋盘稳定性专项；非完整功能验收'} else {'棋盘与本地联机功能及稳定性；非完整游戏验收'})
    stability_only=[bool]$StabilityOnly
    resolution_sweep_enabled=[bool]$ResolutionSweep
    input_method='Godot Input.parse_input_event'
    os_mouse_tested=$false
    visual_status='NOT_RUN'
    not_run_cases=@()
    stability_evidence='stability/resolution_stability.json'
    sources=@()
    stages=@()
}
if (-not $ResolutionSweep) {
    $manifest.not_run_cases += [ordered]@{
        case_id='TC-BOARD-002'
        status='NOT_RUN'
        reason='未启用 -ResolutionSweep；本轮不执行主动四组窗口尺寸轮转。'
    }
}
if ($StabilityOnly) {
    $manifest.excluded_scopes=@('开局领域回归','独立ENet边界用例','TC-BOARD-001/005/006/007/008/009完整GUI用例')
}
foreach ($relative in ($sourcePaths | Sort-Object -Unique)) {
    $absolute = Join-Path $projectRoot $relative
    $hash = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash
    $manifest.sources += [ordered]@{ path=$relative; sha256=$hash }
    if ([IO.Path]::GetExtension($relative) -ne '.png') {
        $copyPath = Join-Path $evidencePath ('source/' + $relative)
        [IO.Directory]::CreateDirectory((Split-Path -Parent $copyPath)) | Out-Null
        Copy-Item -LiteralPath $absolute -Destination $copyPath
    }
}
function Invoke-BoardStage {
    param([string]$Name,[string[]]$EngineArgs,[int]$TimeoutSeconds=120)
    $quoted = foreach ($argument in (@('--path',$projectRoot) + $EngineArgs)) {
        '"' + [Regex]::Replace([Regex]::Replace($argument, '(\\*)"','$1$1\"'),'(\\+)$','$1$1') + '"'
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName=$enginePath
    $process.StartInfo.Arguments=$quoted -join ' '
    $process.StartInfo.UseShellExecute=$false
    $process.StartInfo.CreateNoWindow=$true
    $process.StartInfo.RedirectStandardOutput=$true
    $process.StartInfo.RedirectStandardError=$true
    $process.Start() | Out-Null
    $stdout=$process.StandardOutput.ReadToEndAsync()
    $stderr=$process.StandardError.ReadToEndAsync()
    $timedOut=-not $process.WaitForExit($TimeoutSeconds*1000)
    if ($timedOut) { $process.Kill(); $process.WaitForExit() }
    $process.WaitForExit()
    $output=$stdout.GetAwaiter().GetResult()+[Environment]::NewLine+$stderr.GetAwaiter().GetResult()
    $code=$process.ExitCode
    $process.Dispose()
    [IO.File]::WriteAllText((Join-Path $evidencePath ($Name+'.log')),$output,$utf8)
    $passed=-not $timedOut -and $code -eq 0 -and $output -notmatch '(?m)^\s*(SCRIPT ERROR:|ERROR:|FAIL:)'
    $manifest.stages += [ordered]@{ name=$Name; passed=$passed; exit_code=$code; timed_out=$timedOut; arguments=$EngineArgs; log=$Name+'.log' }
    if ($Name -eq 'network' -and $output -match 'NETWORK_RESULT=([^\r\n]+)') { $manifest.network_evidence=$Matches[1].Trim() }
    Write-Host ($Name + ': ' + $(if ($passed) {'PASSED'} else {'FAILED'}))
    if (-not $passed) { throw "Stage failed: $Name. See $evidencePath" }
}
try {
    Invoke-BoardStage 'import' @('--headless','--editor','--import')
    if (-not $StabilityOnly) {
        Invoke-BoardStage 'domain' @('--headless','--script','res://tests/run_tests.gd','--',"--evidence-dir=$evidencePath","--run-id=$runId")
        Invoke-BoardStage 'network' @('--headless','--script','res://tests/test_room_network.gd','--','--port=27942')
        $guiArgs=@('--script','res://tests/test_board_interface.gd','--',"--evidence-dir=$evidencePath","--run-id=$runId")
        if ($ResolutionSweep) {
            Write-Host '已显式启用尺寸轮转：自动验收窗口会主动切换四组尺寸。'
            $guiArgs += '--resolution-sweep'
        } else {
            Write-Host '功能GUI保持当前窗口尺寸；TC-BOARD-002 主动尺寸轮转为 NOT_RUN。'
        }
        Invoke-BoardStage 'gui' $guiArgs 180
    }
    # 独立目录保留本阶段输入和截图，避免覆盖功能GUI的 input_events.json。
    $stabilityPath=Join-Path $evidencePath 'stability'
    Write-Host '稳定性专项：普通操作和持续停留期间监控尺寸；显示设置往返单独检查。'
    Invoke-BoardStage 'stability' @('--script','res://tests/test_resolution_stability.gd','--',"--evidence-dir=$stabilityPath","--run-id=$runId") 180
    $manifest.automated_status='PASSED'
} catch {
    $manifest.automated_status='FAILED'
    $manifest.error=$_.Exception.Message
    Write-Host $_.Exception.Message
} finally {
    $changed=@($manifest.sources | Where-Object { (Get-FileHash -LiteralPath (Join-Path $projectRoot $_.path) -Algorithm SHA256).Hash -ne $_.sha256 })
    $manifest.source_changes_during_run=@($changed | ForEach-Object { $_.path })
    if ($changed.Count -gt 0) { $manifest.automated_status='INCONCLUSIVE' }
    [IO.File]::WriteAllText((Join-Path $evidencePath 'manifest.json'),($manifest | ConvertTo-Json -Depth 15),$utf8)
}
Write-Host "Evidence: $evidencePath"
Write-Host '结论仅覆盖本轮所选用例；NOT_RUN 不算通过。截图需实际查看，自动通过不代表用户反馈根因已确认或完整游戏已验收。'
if ($manifest.automated_status -ne 'PASSED') { exit 1 }
exit 2
