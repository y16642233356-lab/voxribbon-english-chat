param(
    [string]$Speaker = "",
    [ValidateSet("auto", "cpu", "cuda:0")][string]$Device = "auto",
    [double]$SilenceDb = -42.0,
    [int]$Port = 8765,
    [ValidateSet('en', 'zh')][string]$Language,
    [switch]$Edit,
    [switch]$AISettings,
    [switch]$Reveal
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $ProjectDir ".venv\Scripts\python.exe"
$RuntimeDir = Join-Path $ProjectDir ".runtime"
$ServicePidFile = Join-Path $RuntimeDir 'service.pid'
$HealthUrl = "http://127.0.0.1:$Port/health"
$WebSocketUrl = "ws://127.0.0.1:$Port/ws"

if (-not (Test-Path -LiteralPath $Python)) {
    throw "尚未安装。请先运行 .\install.ps1 -Cuda（NVIDIA）或 .\install.ps1 -Cpu。"
}

function Get-Health {
    try {
        $result = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 2
        if ($result.language -in 'en', 'zh' -and $null -ne $result.clients) { return $result }
        return $null
    }
    catch { return $null }
}

function Stop-FailedService {
    if (-not (Test-Path -LiteralPath $ServicePidFile)) { throw 'Cannot identify the existing VoxRibbon service.' }
    $pidText = (Get-Content -LiteralPath $ServicePidFile -Raw).Trim()
    if ($pidText -notmatch '^\d+$') { throw 'Invalid VoxRibbon service PID.' }
    $root = Get-CimInstance Win32_Process -Filter "ProcessId = $pidText"
    if (-not $root -or $root.ExecutablePath -ne $Python -or $root.CommandLine -notmatch "\s-m\s+system_audio_asr\s+--port\s+$Port(?:\s|$)") {
        throw 'The existing service does not match this VoxRibbon installation.'
    }
    $listeners = @(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if ($listeners.Count -ne 1) { throw 'Cannot identify the service listening on the VoxRibbon port.' }
    $listener = Get-CimInstance Win32_Process -Filter "ProcessId = $($listeners[0].OwningProcess)"
    if (-not $listener -or ($listener.ProcessId -ne $root.ProcessId -and
        ($listener.ParentProcessId -ne $root.ProcessId -or $listener.CommandLine -notmatch "\s-m\s+system_audio_asr\s+--port\s+$Port(?:\s|$)"))) {
        throw 'The VoxRibbon port is occupied by another program.'
    }
    Stop-Process -Id $listener.ProcessId
    Wait-Process -Id $listener.ProcessId -Timeout 5 -ErrorAction SilentlyContinue
    if ($listener.ProcessId -ne $root.ProcessId) {
        Stop-Process -Id $root.ProcessId -ErrorAction SilentlyContinue
    }
}

function Start-ServiceProcess {
    New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null
    $arguments = @('-m', 'system_audio_asr', '--port', "$Port", '--device', $Device, '--silence-db', "$SilenceDb")
    if ($Language) { $arguments += @('--language', $Language) }
    if ($Speaker) { $arguments += @('--speaker', ('"' + $Speaker + '"')) }
    $process = Start-Process -FilePath $Python -ArgumentList $arguments -WorkingDirectory $ProjectDir -RedirectStandardOutput (Join-Path $RuntimeDir 'service.log') -RedirectStandardError (Join-Path $RuntimeDir 'service.err.log') -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $ServicePidFile -Value $process.Id -Encoding ascii
    return $process
}

function Start-VoxRibbon {
    $health = Get-Health
    $service = $null
    if ($health -and ($health.error -or $health.status.state -eq 'stopped' -or ($Language -and $health.language -ne $Language))) {
        Stop-FailedService
        $health = $null
    }
    if (-not $health) {
        $service = Start-ServiceProcess
    }

    $deadline = [DateTime]::UtcNow.AddMinutes(15)
    do {
        Start-Sleep -Milliseconds 750
        $health = Get-Health
        if ($health -and $health.error) {
            throw "ASR 启动失败：$($health.error.message)。查看 .runtime\service.err.log"
        }
        if ($health -and $health.status.state -eq "capturing") { break }
        if ($service -and $service.HasExited) {
            throw "ASR process exited with code $($service.ExitCode). See .runtime\service.err.log."
        }
        if ([DateTime]::UtcNow -gt $deadline) {
            throw "等待 ASR 就绪超时。查看 .runtime\service.err.log"
        }
    } while ($true)

    $overlayArguments = @("--url", $WebSocketUrl)
    if ($AISettings) { $overlayArguments += "--ai-settings" }
    elseif ($Edit) { $overlayArguments += "--edit" }

    $Overlay = Join-Path $ProjectDir "overlay_cs\bin\SystemAudioOverlay.exe"
    if (-not (Test-Path -LiteralPath $Overlay)) {
        & (Join-Path $ProjectDir "build_overlay.ps1")
        if ($LASTEXITCODE -ne 0) { throw "Overlay 构建失败。" }
    }
    $overlayProcess = Get-Process -Name 'SystemAudioOverlay' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $Overlay -and $_.SessionId -eq [System.Diagnostics.Process]::GetCurrentProcess().SessionId }
    if (-not $overlayProcess) {
        Start-Process -FilePath $Overlay -ArgumentList $overlayArguments -WorkingDirectory $ProjectDir -WindowStyle Hidden | Out-Null
    } elseif ($Reveal) {
        $showRequest = $null
        if ([System.Threading.EventWaitHandle]::TryOpenExisting('Local\VoxRibbon.ShowOverlay', [ref]$showRequest)) {
            try { $showRequest.Set() | Out-Null }
            finally { $showRequest.Dispose() }
        }
    }

    Write-Host "VoxRibbon 已就绪：$HealthUrl" -ForegroundColor Green
    Write-Host "设置页面：http://127.0.0.1:$Port/settings" -ForegroundColor Green
    Write-Host "老板键：Ctrl+Alt+H；编辑快捷键：Ctrl+Alt+O" -ForegroundColor Green
}

$launchMutex = New-Object System.Threading.Mutex($false, "Local\VoxRibbon.Launch.$Port")
$ownsMutex = $false
try {
    try { $ownsMutex = $launchMutex.WaitOne([TimeSpan]::FromSeconds(25)) }
    catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
    if ($ownsMutex) { Start-VoxRibbon }
} finally {
    if ($ownsMutex) { $launchMutex.ReleaseMutex() }
    $launchMutex.Dispose()
}
