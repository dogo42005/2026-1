#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Instalador automático de WebODM en Windows 11 via WSL2 + Docker Engine
    Sin Docker Desktop ni GUI. Sin EULA interactiva.

.DESCRIPTION
    FASE 1 (este script): habilita WSL2, instala Ubuntu, configura firewall y
    programa la Fase 2 para que corra automáticamente después del reinicio.

    FASE 2 (instalar_docker_webodm.sh): corre dentro de WSL2, instala Docker
    Engine y arranca WebODM. No requiere intervención manual.

.NOTES
    Ejecutar como Administrador: click derecho -> "Ejecutar con PowerShell"
    Ambos archivos deben estar en la misma carpeta.
#>

$ErrorActionPreference = "Stop"
$INSTALL_DIR  = "C:\webodm_install"
$TAREA_FASE2  = "WebODM-Instalacion-Fase2"
$TAREA_INICIO = "WebODM-Autostart"

function Log  { param($m) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $m" -ForegroundColor Cyan }
function OK   { param($m) Write-Host "[OK]  $m" -ForegroundColor Green }
function WARN { param($m) Write-Host "[!]   $m" -ForegroundColor Yellow }
function ERR  { param($m) Write-Host "[ERR] $m" -ForegroundColor Red; exit 1 }

Log "=== Instalador WebODM para Windows 11 ==="

# ─────────────────────────────────────────────────────────────────────────────
# Si WebODM ya está instalado: solo arrancar
# ─────────────────────────────────────────────────────────────────────────────
$ubuntuInstalado = wsl --list --quiet 2>$null | Where-Object { $_ -match "Ubuntu" }
$tareaInicio = Get-ScheduledTask -TaskName $TAREA_INICIO -ErrorAction SilentlyContinue

if ($ubuntuInstalado -and $tareaInicio) {
    Log "WebODM ya instalado. Iniciando..."
    wsl -d Ubuntu -u root -- bash -c "service docker start 2>/dev/null || true; cd ~/WebODM && ./webodm.sh start --port 8000"
    OK "WebODM corriendo en http://localhost:8000"
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Copiar bash script al disco local (C:\ es accesible desde WSL2 como /mnt/c/)
# Se convierte CRLF -> LF para que bash lo lea correctamente
# ─────────────────────────────────────────────────────────────────────────────
$bashSrc = Join-Path $PSScriptRoot "instalar_docker_webodm.sh"
if (-not (Test-Path $bashSrc)) {
    ERR "No se encontró 'instalar_docker_webodm.sh' junto a este script."
}

New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
$contenido = Get-Content $bashSrc -Raw
$contenido = $contenido -replace "`r`n", "`n"   # CRLF -> LF
[System.IO.File]::WriteAllText(
    "$INSTALL_DIR\instalar_docker_webodm.sh",
    $contenido,
    [System.Text.Encoding]::UTF8
)
OK "Script de instalación copiado a $INSTALL_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# Configurar WSL2 en modo red espejo (Windows 11 22H2+)
# Con esto WSL2 comparte la misma IP que Windows -> no necesita port proxy
# ─────────────────────────────────────────────────────────────────────────────
$wslConfig = "$env:USERPROFILE\.wslconfig"
Set-Content -Path $wslConfig -Value "[wsl2]`nnetworkingMode=mirrored`n" -Encoding UTF8
OK "WSL2 configurado en modo red espejo (misma IP que Windows)"

# ─────────────────────────────────────────────────────────────────────────────
# Habilitar características de Windows necesarias para WSL2
# ─────────────────────────────────────────────────────────────────────────────
$wslOK = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State -eq "Enabled"
$vmOK  = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State -eq "Enabled"

$necesitaReinicio = $false

if (-not $wslOK) {
    Log "Habilitando WSL..."
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
    $necesitaReinicio = $true
}
if (-not $vmOK) {
    Log "Habilitando Plataforma de Máquina Virtual (requerida por WSL2)..."
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    $necesitaReinicio = $true
}
if (-not $necesitaReinicio) { OK "Características WSL2 ya habilitadas" }

# ─────────────────────────────────────────────────────────────────────────────
# Instalar Ubuntu en WSL2 (sin lanzar, sin prompt de usuario)
# ─────────────────────────────────────────────────────────────────────────────
if (-not $ubuntuInstalado) {
    Log "Instalando Ubuntu en WSL2..."
    wsl --set-default-version 2 2>$null
    wsl --install -d Ubuntu --web-download --no-launch
    OK "Ubuntu instalado en WSL2"
} else {
    OK "Ubuntu ya instalado en WSL2"
}

# ─────────────────────────────────────────────────────────────────────────────
# Regla de Firewall de Windows para puerto 8000
# ─────────────────────────────────────────────────────────────────────────────
if (-not (Get-NetFirewallRule -DisplayName "WebODM-8000" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -DisplayName "WebODM-8000" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 8000 `
        -Action Allow | Out-Null
    OK "Firewall: puerto 8000 TCP abierto para conexiones entrantes"
} else {
    OK "Firewall: regla para puerto 8000 ya existe"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tarea programada: Fase 2 corre automáticamente al volver a iniciar sesión
# ─────────────────────────────────────────────────────────────────────────────
$accion     = New-ScheduledTaskAction `
    -Execute "wsl.exe" `
    -Argument "-d Ubuntu -u root -- bash /mnt/c/webodm_install/instalar_docker_webodm.sh"
$disparador = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$config     = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -RunOnlyIfNetworkAvailable:$false
$principal  = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest

Register-ScheduledTask `
    -TaskName $TAREA_FASE2 `
    -Action $accion `
    -Trigger $disparador `
    -Settings $config `
    -Principal $principal `
    -Force | Out-Null

OK "Tarea programada '$TAREA_FASE2' creada: continuará la instalación al reiniciar"

# ─────────────────────────────────────────────────────────────────────────────
# Reinicio o ejecución directa
# ─────────────────────────────────────────────────────────────────────────────
if ($necesitaReinicio) {
    Write-Host ""
    WARN "Es necesario reiniciar para activar WSL2."
    WARN "Al volver a iniciar sesión, Docker + WebODM se instalan solos."
    WARN "No es necesario hacer nada mas."
    Write-Host ""
    $r = Read-Host "Reiniciar ahora? (s/n)"
    if ($r -eq "s") {
        Restart-Computer -Force
    } else {
        WARN "Reinicia manualmente. La instalacion continuara sola al volver a iniciar sesion."
    }
} else {
    Log "WSL2 ya activo. Ejecutando instalacion directamente..."
    wsl -d Ubuntu -u root -- bash /mnt/c/webodm_install/instalar_docker_webodm.sh
}
