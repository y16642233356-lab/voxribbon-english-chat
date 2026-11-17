param([switch]$ShowErrors)

$ErrorActionPreference = 'Stop'
$env:LOCALAPPDATA = [Environment]::GetFolderPath('LocalApplicationData')
$env:VOXRIBBON_ENGLISH_MODEL_DIR = Join-Path $PSScriptRoot 'models\whisper-tiny.en'
$env:VOXRIBBON_TRANSLATION_MODEL_DIR = Join-Path $PSScriptRoot 'models\opus-mt-en-zh'
$env:VOXRIBBON_TRANSLATION_DEVICE = 'cpu'
$env:PYTHONUTF8 = '1'

try {
    Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 2 | Out-Null
} catch {
    $ollama = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($ollama) {
        Start-Process -FilePath $ollama.Source -ArgumentList 'serve' -WindowStyle Hidden
    }
}

try {
    & (Join-Path $PSScriptRoot 'launch.ps1') -Device cpu -Language en -Reveal
} catch {
    if ($ShowErrors) {
        $shell = New-Object -ComObject WScript.Shell
        $null = $shell.Popup($_.Exception.Message, 0, 'VoxRibbon Startup', 16)
    }
    throw
}
