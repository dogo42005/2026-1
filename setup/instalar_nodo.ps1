# instalar_nodo.ps1
# Instala WSL2, Git, Docker Desktop, Python y WebODM en el nodo remoto (146.155.38.81)
# Ejecutar con derechos de Administrador en el PC remoto (via Escritorio Remoto o SSH)
#
# Uso:
#   PowerShell -ExecutionPolicy Bypass -File instalar_nodo.ps1

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$WEBODM_DIR  = "C:\WebODM"
$PIPELINE_DIR = "C:\WebODM\pipeline"
$WEBODM_PORT = 8000

function Write-Step($msg) { Write-Host "`n[>>] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK] $msg"  -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!]  $msg"  -ForegroundColor Yellow }

Write-Host "============================================" -ForegroundColor Magenta
Write-Host " Instalador nodo fotogrametrico IPRE UC" -ForegroundColor Magenta
Write-Host " Objetivo: $($env:COMPUTERNAME)" -ForegroundColor Magenta
Write-Host "============================================`n" -ForegroundColor Magenta

# ─── 1. WSL2 ───────────────────────────────────────────
Write-Step "Verificando WSL2..."
$wslVersion = wsl --list --verbose 2>$null
if ($LASTEXITCODE -ne 0 -or -not $wslVersion) {
    Write-Warn "WSL2 no instalado. Instalando..."
    wsl --install --no-distribution
    Write-Warn "REINICIA EL PC y vuelve a ejecutar este script."
    Read-Host "Presiona Enter para cerrar"
    exit 0
}
Write-Ok "WSL2 disponible."

# ─── 2. Git ────────────────────────────────────────────
Write-Step "Verificando Git..."
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  Instalando Git via winget..."
    winget install --id Git.Git -e --source winget --silent `
        --accept-package-agreements --accept-source-agreements
    $env:PATH += ";C:\Program Files\Git\bin;C:\Program Files\Git\cmd"
    Write-Ok "Git instalado."
} else {
    Write-Ok "Git ya instalado: $(git --version)"
}

# ─── 3. Docker Desktop ─────────────────────────────────
Write-Step "Verificando Docker Desktop..."
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"
    $dockerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
    Write-Host "  Descargando Docker Desktop (~600 MB)..."
    Invoke-WebRequest -Uri $dockerUrl -OutFile $installerPath -UseBasicParsing
    Write-Host "  Instalando Docker Desktop (puede tardar varios minutos)..."
    Start-Process -FilePath $installerPath `
        -ArgumentList "install", "--quiet", "--accept-license" `
        -Wait
    Remove-Item $installerPath -Force
    Write-Ok "Docker Desktop instalado."
    Write-Warn "REINICIA EL PC para activar Docker, luego ejecuta este script de nuevo."
    Read-Host "Presiona Enter para cerrar"
    exit 0
} else {
    Write-Ok "Docker ya instalado: $(docker --version)"
}

# ─── 4. Python ─────────────────────────────────────────
Write-Step "Verificando Python..."
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "  Instalando Python 3.11 via winget..."
    winget install --id Python.Python.3.11 -e --silent `
        --accept-package-agreements --accept-source-agreements
    $env:PATH += ";$env:LOCALAPPDATA\Programs\Python\Python311"
    Write-Ok "Python instalado."
} else {
    Write-Ok "Python ya instalado: $(python --version)"
}

Write-Step "Instalando dependencias Python del pipeline..."
python -m pip install requests tqdm --quiet
Write-Ok "Dependencias instaladas."

# ─── 5. WebODM ─────────────────────────────────────────
Write-Step "Configurando WebODM en $WEBODM_DIR..."
if (-not (Test-Path "$WEBODM_DIR\WebODM")) {
    New-Item -ItemType Directory -Force -Path $WEBODM_DIR | Out-Null
    Set-Location $WEBODM_DIR
    git clone https://github.com/WebODM/WebODM --config core.autocrlf=input --depth 1
    Write-Ok "WebODM clonado."
} else {
    Write-Ok "WebODM ya clonado en $WEBODM_DIR\WebODM"
}

# ─── 6. Copiar pipeline al nodo ────────────────────────
Write-Step "Copiando scripts del pipeline al nodo..."
New-Item -ItemType Directory -Force -Path $PIPELINE_DIR | Out-Null
$scriptOrigen = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $scriptOrigen

foreach ($archivo in @("webodm_pipeline.py", "config.json", "config_remoto.json")) {
    $src = Join-Path $raiz $archivo
    if (Test-Path $src) {
        Copy-Item $src $PIPELINE_DIR -Force
        Write-Ok "Copiado: $archivo"
    }
}

# ─── 7. Regla de firewall puerto 8000 ──────────────────
Write-Step "Configurando firewall (puerto $WEBODM_PORT)..."
$regla = Get-NetFirewallRule -DisplayName "WebODM-$WEBODM_PORT" -ErrorAction SilentlyContinue
if (-not $regla) {
    New-NetFirewallRule `
        -DisplayName "WebODM-$WEBODM_PORT" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $WEBODM_PORT `
        -Action Allow | Out-Null
    Write-Ok "Puerto $WEBODM_PORT abierto en firewall."
} else {
    Write-Ok "Regla de firewall ya existe."
}

# ─── Resumen final ─────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Green
Write-Host " INSTALACION COMPLETADA" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Pasos siguientes:"
Write-Host "  1. Abre Docker Desktop y espera que este activo"
Write-Host "  2. Ejecuta:  .\setup\iniciar_webodm.bat"
Write-Host "  3. Espera ~15 min la primera vez (descarga imagenes Docker)"
Write-Host "  4. Desde tu PC local accede a: http://146.155.38.81:$WEBODM_PORT"
Write-Host ""
