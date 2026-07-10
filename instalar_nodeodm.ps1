#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Instala NodeODM (motor de procesamiento) en Windows 11 via WSL2.
    Más liviano que WebODM completo. Para PCs trabajadores.
    Ejecutar como Administrador en cada PC trabajador.
#>

$ErrorActionPreference = "Stop"
$INSTALL_DIR  = "C:\webodm_install"
$TAREA_FASE2  = "NodeODM-Instalacion-Fase2"
$TAREA_INICIO = "NodeODM-Autostart"

function Log  { param($m) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $m" -ForegroundColor Cyan }
function OK   { param($m) Write-Host "[OK]  $m" -ForegroundColor Green }
function WARN { param($m) Write-Host "[!]   $m" -ForegroundColor Yellow }
function ERR  { param($m) Write-Host "[ERR] $m" -ForegroundColor Red; exit 1 }

Log "=== Instalador NodeODM para Windows 11 ==="

# ── Si ya está instalado: solo arrancar ───────────────────────────────────
$ubuntuInstalado = wsl --list --quiet 2>$null | Where-Object { $_ -match "Ubuntu" }
$tareaInicio = Get-ScheduledTask -TaskName $TAREA_INICIO -ErrorAction SilentlyContinue

if ($ubuntuInstalado -and $tareaInicio) {
    Log "NodeODM ya instalado. Iniciando..."
    wsl -d Ubuntu -u root -- bash -c "service docker start 2>/dev/null || true; docker start nodeodm 2>/dev/null || docker run -d --name nodeodm -p 3000:3000 opendronemap/nodeodm"
    OK "NodeODM corriendo en puerto 3000"
    exit 0
}

# ── Copiar bash script (CRLF -> LF) ──────────────────────────────────────
$bashSrc = Join-Path $PSScriptRoot "instalar_nodeodm.sh"
if (-not (Test-Path $bashSrc)) { ERR "No se encontró 'instalar_nodeodm.sh' junto a este script." }

New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
$contenido = Get-Content $bashSrc -Raw
$contenido = $contenido -replace "`r`n", "`n"
[System.IO.File]::WriteAllText("$INSTALL_DIR\instalar_nodeodm.sh", $contenido, [System.Text.Encoding]::UTF8)
OK "Script copiado a $INSTALL_DIR"

# ── WSL2 modo red espejo ──────────────────────────────────────────────────
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value "[wsl2]`nnetworkingMode=mirrored`n" -Encoding UTF8
OK "WSL2: modo red espejo configurado"

# ── Habilitar características WSL2 ───────────────────────────────────────
$wslOK = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State -eq "Enabled"
$vmOK  = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State -eq "Enabled"
$necesitaReinicio = $false

if (-not $wslOK) {
    Log "Habilitando WSL..."
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
    $necesitaReinicio = $true
}
if (-not $vmOK) {
    Log "Habilitando Plataforma de Máquina Virtual..."
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    $necesitaReinicio = $true
}
if (-not $necesitaReinicio) { OK "Características WSL2 ya habilitadas" }

# ── Instalar Ubuntu ───────────────────────────────────────────────────────
if (-not $ubuntuInstalado) {
    Log "Instalando Ubuntu en WSL2..."
    wsl --set-default-version 2 2>$null
    wsl --install -d Ubuntu --web-download --no-launch
    OK "Ubuntu instalado"
} else {
    OK "Ubuntu ya instalado"
}

# ── Firewall: puerto 3000 (NodeODM) ──────────────────────────────────────
if (-not (Get-NetFirewallRule -DisplayName "NodeODM-3000" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "NodeODM-3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow | Out-Null
    OK "Firewall: puerto 3000 TCP abierto"
} else {
    OK "Firewall: regla puerto 3000 ya existe"
}

# ── Tarea programada para Fase 2 ─────────────────────────────────────────
$accion     = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -u root -- bash /mnt/c/webodm_install/instalar_nodeodm.sh"
$disparador = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$config     = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -RunOnlyIfNetworkAvailable:$false
$principal  = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
Register-ScheduledTask -TaskName $TAREA_FASE2 -Action $accion -Trigger $disparador -Settings $config -Principal $principal -Force | Out-Null
OK "Tarea programada creada"

# ── Reinicio o ejecución directa ─────────────────────────────────────────
if ($necesitaReinicio) {
    Write-Host ""
    WARN "Se necesita reiniciar para activar WSL2."
    WARN "Al volver a iniciar sesión, Docker + NodeODM se instalan solos."
    $r = Read-Host "Reiniciar ahora? (s/n)"
    if ($r -eq "s") { Restart-Computer -Force }
    else { WARN "Reinicia manualmente. La instalación continuará sola al volver a iniciar sesión." }
} else {
    Log "WSL2 activo. Ejecutando instalación directamente..."
    wsl -d Ubuntu -u root -- bash /mnt/c/webodm_install/instalar_nodeodm.sh
}
