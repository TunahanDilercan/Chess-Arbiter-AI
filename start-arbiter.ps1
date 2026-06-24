# ─────────────────────────────────────────────────────────────────────────────
# Arbiter AI — tek-tik baslatici
#
#   1. Docker Desktop'i ayaga kaldirir (kapaliysa)
#   2. backend + worker + postgres + redis (docker compose)
#   3. web'i URETIM modunda baslatir (next start, :3000)
#   4. ngrok stabil tunelini basic-auth ile acar
#   5. Telefondan girilecek URL'i + sifreyi ekrana basar
#
# Kullanim:  sag tik > "Run with PowerShell"  ya da  Arbiter-Baslat.cmd cift tikla
#   -Rebuild : web'i sifirdan yeniden derle (kod degistiyse)
# ─────────────────────────────────────────────────────────────────────────────
param([switch]$Rebuild)

$ErrorActionPreference = "Stop"
$Root      = $PSScriptRoot
$Web       = Join-Path $Root "web"
$Compose   = Join-Path $Root "docker-compose.yml"
$PublicUrl = "https://stubbly-flatfoot-trimming.ngrok-free.dev"

# Kimlik bilgilerini repoya GIRMEYECEK sekilde ngrok.yml'den oku (tek kaynak).
# Boylece hicbir commit'lenen dosyada duz sifre durmaz.
$NgrokYml  = Join-Path $env:LOCALAPPDATA "ngrok\ngrok.yml"
$BasicUser = "arbiter"; $BasicPass = "(ngrok.yml)"
if (Test-Path $NgrokYml) {
    $m = Select-String -Path $NgrokYml -Pattern '"([^":]+):([^"]+)"' | Select-Object -First 1
    if ($m) { $BasicUser = $m.Matches[0].Groups[1].Value; $BasicPass = $m.Matches[0].Groups[2].Value }
}

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    [!]  $m" -ForegroundColor Yellow }

Write-Host "================ Arbiter AI baslatiliyor ================" -ForegroundColor White

# 1) Docker Desktop ----------------------------------------------------------
Step "Docker kontrol ediliyor"
docker ps *> $null
if (-not $?) {
    Warn "Docker kapali, Docker Desktop aciliyor..."
    $dd = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dd) { Start-Process $dd }
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 3
        docker ps *> $null
        if ($?) { break }
        Write-Host "    ...daemon bekleniyor ($([int]($i*3))s)" -ForegroundColor DarkGray
    }
    docker ps *> $null
    if (-not $?) { Warn "Docker baslatilamadi. Docker Desktop'i elle ac ve tekrar dene."; Read-Host "Enter ile cik"; exit 1 }
}
Ok "Docker hazir"

# 2) Backend stack -----------------------------------------------------------
Step "Backend stack (backend/worker/postgres/redis)"
docker compose -f $Compose up -d 2>&1 | Out-Null
for ($i = 0; $i -lt 30; $i++) {
    try { $h = Invoke-WebRequest "http://localhost:8000/health" -UseBasicParsing -TimeoutSec 3
          if ($h.StatusCode -eq 200) { break } } catch {}
    Start-Sleep -Seconds 2
}
try { $h = Invoke-WebRequest "http://localhost:8000/health" -UseBasicParsing -TimeoutSec 3; Ok "Backend saglikli: $($h.Content)" }
catch { Warn "Backend /health yanit vermedi (yine de devam)" }

# 3) Web (uretim modu) -------------------------------------------------------
Step "Web arayuzu (uretim derlemesi, :3000)"
$needBuild = $Rebuild -or -not (Test-Path (Join-Path $Web ".next"))
if (-not (Test-Path (Join-Path $Web "node_modules"))) {
    Warn "node_modules yok, npm install calistiriliyor..."
    Push-Location $Web; npm install | Out-Null; Pop-Location
}
if ($needBuild) {
    Warn "Web derleniyor (next build) — ilk seferde biraz surebilir..."
    Push-Location $Web; npm run build; Pop-Location
    if (-not $?) { Warn "Web derlemesi basarisiz."; Read-Host "Enter ile cik"; exit 1 }
    Ok "Web derlendi"
}
Start-Process powershell -ArgumentList "-NoExit","-Command","cd `"$Web`"; npm run start" -WindowStyle Minimized
for ($i = 0; $i -lt 30; $i++) {
    try { $r = Invoke-WebRequest "http://localhost:3000" -UseBasicParsing -TimeoutSec 3
          if ($r.StatusCode -eq 200) { break } } catch {}
    Start-Sleep -Seconds 2
}
Ok "Web ayakta: http://localhost:3000"

# 4) ngrok tunel -------------------------------------------------------------
Step "ngrok tuneli (basic-auth korumali)"
Start-Process powershell -ArgumentList "-NoExit","-Command","ngrok start arbiter" -WindowStyle Minimized
Start-Sleep -Seconds 4
Ok "ngrok baslatildi"

# 5) Ozet --------------------------------------------------------------------
$lan = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" } |
        Select-Object -First 1 -ExpandProperty IPAddress)

Write-Host "`n================ HAZIR ================" -ForegroundColor Green
Write-Host "Telefondan (her yerden, internet):" -ForegroundColor White
Write-Host "   $PublicUrl" -ForegroundColor Yellow
Write-Host "   kullanici: $BasicUser" -ForegroundColor Yellow
Write-Host "   sifre    : $BasicPass" -ForegroundColor Yellow
if ($lan) {
  Write-Host "`nAyni wifi agindaysan (sifresiz, sadece yerel ag):" -ForegroundColor White
  Write-Host "   http://${lan}:3000" -ForegroundColor Gray
}
Write-Host "`nBilgisayarda:  http://localhost:3000" -ForegroundColor White
Write-Host "Durdurmak icin: stop-arbiter.ps1  (ya da acilan pencereleri kapat)" -ForegroundColor DarkGray
Write-Host "======================================`n" -ForegroundColor Green
Read-Host "Bu pencereyi kapatabilirsin (servisler arka planda calisir). Enter"
