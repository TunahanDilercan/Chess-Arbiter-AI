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
#   -Rebuild : backend'i temiz tabandan ve web'i yeniden derle
# ─────────────────────────────────────────────────────────────────────────────
param([switch]$Rebuild, [switch]$LocalOnly, [switch]$NoWait)

$ErrorActionPreference = "Stop"
$Root      = $PSScriptRoot
$Web       = Join-Path $Root "web"
$Compose   = Join-Path $Root "docker-compose.yml"
$Override  = Join-Path $Root "docker-compose.override.yml"
$ComposeArgs = @("compose", "--project-directory", $Root, "-f", $Compose)
if (Test-Path $Override) { $ComposeArgs += @("-f", $Override) }
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
function Run-Checked($Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable basarisiz oldu (cikis: $LASTEXITCODE)." }
}

Write-Host "================ Arbiter AI baslatiliyor ================" -ForegroundColor White

# 1) Docker Desktop ----------------------------------------------------------
Step "Docker kontrol ediliyor"
docker ps *> $null
if (-not $?) {
    Warn "Docker kapali, Docker Desktop aciliyor..."
    $dd = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dd) { Start-Process $dd -WindowStyle Hidden }
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
$buildArgs = $ComposeArgs + @("build")
if (-not $Rebuild) {
    foreach ($candidate in @("arbiter-ai-app:local", "arbiter-ai-backend:latest")) {
        & docker image inspect $candidate *> $null
        if ($LASTEXITCODE -eq 0) {
            $buildArgs += @("--build-arg", "RUNTIME_BASE=$candidate")
            break
        }
    }
}
Run-Checked "docker" ($buildArgs + @("backend"))
Run-Checked "docker" ($ComposeArgs + @("up", "-d", "--no-build", "backend", "worker"))
$backendReady = $false
for ($i = 0; $i -lt 30; $i++) {
    try { $h = Invoke-WebRequest "http://localhost:8000/health" -UseBasicParsing -TimeoutSec 3
          if ($h.StatusCode -eq 200) { $backendReady = $true; break } } catch {}
    Start-Sleep -Seconds 2
}
if (-not $backendReady) { throw "Backend hazir olmadi. Docker backend/migrate loglarini kontrol et." }
Ok "Backend saglikli: $($h.Content)"

# 3) Web (uretim modu) -------------------------------------------------------
Step "Web arayuzu (uretim derlemesi, :3000)"
$buildId = Join-Path $Web ".next\BUILD_ID"
$needBuild = $Rebuild -or -not (Test-Path $buildId)
if (-not $needBuild) {
    $builtAt = (Get-Item $buildId).LastWriteTimeUtc
    $inputs = @("app", "components", "lib", "public", "package.json", "package-lock.json", "next.config.mjs", "tsconfig.json")
    foreach ($inputPath in $inputs) {
        $fullPath = Join-Path $Web $inputPath
        if (Test-Path $fullPath) {
            if (Get-ChildItem $fullPath -Recurse -File | Where-Object { $_.LastWriteTimeUtc -gt $builtAt } | Select-Object -First 1) {
                $needBuild = $true
                break
            }
        }
    }
}
$listener = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $existing = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
    if ($existing.CommandLine -notlike "*$Web*node_modules*next*") {
        throw "3000 portu baska bir uygulama tarafindan kullaniliyor."
    }
    if ($needBuild) { Stop-Process -Id $listener.OwningProcess -Force }
}
if (-not (Test-Path (Join-Path $Web "node_modules"))) {
    Warn "node_modules yok, npm install calistiriliyor..."
    Push-Location $Web
    try { Run-Checked "npm.cmd" @("ci") } finally { Pop-Location }
}
if ($needBuild) {
    Warn "Web derleniyor (next build), ilk seferde biraz surebilir..."
    Push-Location $Web
    try { Run-Checked "npm.cmd" @("run", "build") } finally { Pop-Location }
    Ok "Web derlendi"
}
if (-not $listener -or $needBuild) {
    $node = (Get-Command node).Source
    $next = Join-Path $Web "node_modules\next\dist\bin\next"
    Start-Process $node -ArgumentList @("`"$next`"", "start", "-p", "3000") -WorkingDirectory $Web -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Web "web-server.log") -RedirectStandardError (Join-Path $Web "web-server-error.log")
}
$webReady = $false
for ($i = 0; $i -lt 30; $i++) {
    try { $r = Invoke-WebRequest "http://localhost:3000" -UseBasicParsing -TimeoutSec 3
          if ($r.StatusCode -eq 200) { $webReady = $true; break } } catch {}
    Start-Sleep -Seconds 2
}
if (-not $webReady) { throw "Web arayuzu hazir olmadi. web-server-error.log dosyasini kontrol et." }
Ok "Web ayakta: http://localhost:3000"

# 4) ngrok tunel -------------------------------------------------------------
if (-not $LocalOnly) {
    Step "ngrok tuneli (basic-auth korumali)"
    if (-not (Get-Process ngrok -ErrorAction SilentlyContinue)) {
        Start-Process ngrok -ArgumentList @("start", "arbiter") -WindowStyle Hidden
        Start-Sleep -Seconds 4
    }
    if (-not (Get-Process ngrok -ErrorAction SilentlyContinue)) { throw "ngrok baslatilamadi." }
    Ok "ngrok baslatildi"
}

# 5) Ozet --------------------------------------------------------------------
$lan = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" } |
        Select-Object -First 1 -ExpandProperty IPAddress)

Write-Host "`n================ HAZIR ================" -ForegroundColor Green
if (-not $LocalOnly) {
    Write-Host "Telefondan (her yerden, internet):" -ForegroundColor White
    Write-Host "   $PublicUrl" -ForegroundColor Yellow
    Write-Host "   kullanici: $BasicUser" -ForegroundColor Yellow
    Write-Host "   sifre    : $BasicPass" -ForegroundColor Yellow
}
if ($lan) {
  Write-Host "`nAyni wifi agindaysan (sifresiz, sadece yerel ag):" -ForegroundColor White
  Write-Host "   http://${lan}:3000" -ForegroundColor Gray
}
Write-Host "`nBilgisayarda:  http://localhost:3000" -ForegroundColor White
Write-Host "Durdurmak icin: stop-arbiter.ps1  (ya da acilan pencereleri kapat)" -ForegroundColor DarkGray
Write-Host "======================================`n" -ForegroundColor Green
if (-not $NoWait) { Read-Host "Bu pencereyi kapatabilirsin (servisler arka planda calisir). Enter" }
