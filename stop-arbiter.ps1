# Arbiter AI — durdur: ngrok + web penceresini kapat, docker stack'i indir.
$ErrorActionPreference = "SilentlyContinue"
$Root    = $PSScriptRoot
$Compose = Join-Path $Root "docker-compose.yml"

Write-Host "==> ngrok durduruluyor"      -ForegroundColor Cyan
Get-Process ngrok -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "==> web (next start) durduruluyor" -ForegroundColor Cyan
# :3000 dinleyen node surecini bul ve kapat
$pids = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue).OwningProcess | Sort-Object -Unique
foreach ($p in $pids) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }

Write-Host "==> docker stack indiriliyor" -ForegroundColor Cyan
docker compose -f $Compose down 2>&1 | Out-Null

Write-Host "Durduruldu." -ForegroundColor Green
Start-Sleep -Seconds 1
