# Inicia el puente si existe Python y lo cierra al salir del juego.
$ErrorActionPreference = 'Stop'
$portable = Join-Path $PSScriptRoot 'PuduFantasy.exe'
$engine = Join-Path $PSScriptRoot 'tools/love-win64/love.exe'
$gameArgs = @($PSScriptRoot)
if (Test-Path -LiteralPath $portable) {
    $engine = $portable
    $gameArgs = @()
}
if (-not (Test-Path -LiteralPath $engine)) {
    $installed = Get-Command love.exe -ErrorAction SilentlyContinue
    if ($installed) { $engine = $installed.Source }
    else { throw 'Instala LOVE 11.5 o coloca su carpeta portable en tools/love-win64.' }
}

$port = $env:PUDU_BATTLE_PORT
if (-not $port) {
    $config = Join-Path $PSScriptRoot '.env'
    if (Test-Path -LiteralPath $config) {
        $line = Select-String -LiteralPath $config -Pattern '^\s*PUDU_BATTLE_PORT\s*=\s*(\d+)\s*$' | Select-Object -First 1
        if ($line) { $port = $line.Matches[0].Groups[1].Value }
    }
}
if (-not $port) { $port = '18425' }
if ($port -notmatch '^\d{1,5}$' -or [int]$port -lt 1 -or [int]$port -gt 65535) {
    throw 'PUDU_BATTLE_PORT debe ser un puerto entre 1 y 65535.'
}
$env:PUDU_BATTLE_PORT = $port

function Test-PuduBridge {
    try {
        $health = Invoke-RestMethod -UseBasicParsing -TimeoutSec 1 -Uri "http://127.0.0.1:$port/health"
        return ($health.ok -and $health.sprite_model)
    } catch { return $false }
}

$bridgeProcess = $null
try {
    if ($args -notcontains '--mock' -and -not (Test-PuduBridge)) {
        $python = Get-Command py.exe -ErrorAction SilentlyContinue
        $bridgeArgs = @('-3', 'ai_bridge.py')
        if (-not $python) {
            $python = Get-Command python.exe -ErrorAction SilentlyContinue
            $bridgeArgs = @('ai_bridge.py')
        }
        if ($python -and $python.Source -notlike '*\Microsoft\WindowsApps\python.exe') {
            try {
                $bridgeProcess = Start-Process -FilePath $python.Source -ArgumentList $bridgeArgs -WorkingDirectory $PSScriptRoot -PassThru -WindowStyle Hidden
                for ($i = 0; $i -lt 10; $i++) {
                    if ($bridgeProcess.HasExited -or (Test-PuduBridge)) { break }
                    Start-Sleep -Milliseconds 100
                }
            } catch { Write-Host 'El combate usará el juez local de Lua.' }
        }
    }
    & $engine @gameArgs @args | Out-Host
    $gameExit = $LASTEXITCODE
} finally {
    if ($bridgeProcess -and -not $bridgeProcess.HasExited) {
        # py.exe can start a child interpreter; stop only the tree this launcher started.
        & taskkill.exe /PID $bridgeProcess.Id /T /F | Out-Null
    }
}
exit $gameExit
