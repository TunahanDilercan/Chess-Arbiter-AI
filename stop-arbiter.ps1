# Arbiter AI — durdur: ngrok + web penceresini kapat, docker stack'i indir.
$ErrorActionPreference = "Stop"
$Root    = $PSScriptRoot
$Compose = Join-Path $Root "docker-compose.yml"
$ComposeArgs = @("compose", "--project-directory", $Root, "-f", $Compose)
$Override = Join-Path $Root "docker-compose.override.yml"
if (Test-Path $Override) { $ComposeArgs += @("-f", $Override) }

Write-Host "==> ngrok durduruluyor"      -ForegroundColor Cyan
Get-CimInstance Win32_Process -Filter "Name='ngrok.exe'" |
    Where-Object { $_.CommandLine -match '\bstart\s+arbiter\b' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host "==> web (next start) durduruluyor" -ForegroundColor Cyan
# Yalnizca bu projeye ait web surecini kapat.
$pids = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue).OwningProcess | Sort-Object -Unique
foreach ($p in $pids) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $p"
    if ($process.CommandLine -like "*$Root\web*node_modules*next*") {
        Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "==> docker stack indiriliyor" -ForegroundColor Cyan
& docker @ComposeArgs down
if ($LASTEXITCODE -ne 0) { throw "Docker servisleri durdurulamadi." }

Write-Host "Durduruldu." -ForegroundColor Green
Start-Sleep -Seconds 1
