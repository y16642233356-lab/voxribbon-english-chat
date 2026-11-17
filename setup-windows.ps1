$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    $env:PYTHONUTF8 = '1'
    $probe = 'import struct, sys; print(int(sys.version_info[:2] == (3, 12) and struct.calcsize(''P'') == 8))'
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    $pythonArgs = @('-3.12')
    if (!$launcher -or (& $launcher.Source @pythonArgs -c $probe 2>$null) -ne '1') {
        $launcher = Get-Command python.exe -ErrorAction SilentlyContinue
        $pythonArgs = @()
        if (!$launcher -or (& $launcher.Source -c $probe 2>$null) -ne '1') {
            throw 'Install 64-bit Python 3.12 and enable the Python launcher or Add Python to PATH. See the README.'
        }
    }

    $venv = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
    if (!(Test-Path -LiteralPath $venv)) {
        & $launcher.Source @pythonArgs -m venv .venv
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the local Python environment.' }
    }
    & $venv -m pip --disable-pip-version-check install --retries 3 -r requirements-windows.txt
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed. Check the connection and run 01-Install.cmd again.' }
    & $venv -m pip check
    if ($LASTEXITCODE -ne 0) { throw 'Some dependencies are incompatible.' }
    & $venv download-models.py
    if ($LASTEXITCODE -ne 0) { throw 'Model download failed. Run 01-Install.cmd again to retry the missing files.' }
    & $venv -c "from system_audio_asr.settings import CONFIG_PATH, update_from_web; CONFIG_PATH.exists() or update_from_web({'asrLanguage':'en','liveTranslateEnabled':True,'width':900,'height':400,'fontSize':17})"
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize subtitle settings.' }
    if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'overlay_cs\bin\SystemAudioOverlay.exe'))) {
        & (Join-Path $PSScriptRoot 'build_overlay.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'Could not build the desktop overlay.' }
    }
    Write-Host 'Installation completed. Double-click 02-Start.cmd.' -ForegroundColor Green
} finally {
    Pop-Location
}
