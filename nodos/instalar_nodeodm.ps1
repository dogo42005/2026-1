#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Instalador automático de NodeODM en Windows 11 via WSL2 + Docker Engine.
    Para PCs trabajadores del cluster fotogramétrico.

.DESCRIPTION
    FASE 1 (este script, PowerShell): habilita WSL2, instala Ubuntu, configura
    red espejo, abre firewall, crea tarea WSL-KeepAlive y programa la Fase 2.

    FASE 2 (instalar_nodeodm.sh, bash): corre dentro de WSL2, instala
    Docker Engine con systemd, arranca el contenedor NodeODM.

.NOTES
    Ejecutar como Administrador.
    Ambos archivos deben estar en la misma carpeta.
#>

$ErrorActionPreference = "Stop"
$INSTALL_DIR  = "C:\webodm_install"
$TAREA_FASE2  = "NodeODM-Instalacion-Fase2"
$TAREA_INICIO = "NodeODM-Autostart"
$TAREA_KEEPALIVE = "WSL-KeepAlive"

function Log  { param($m) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $m" -ForegroundColor Cyan }
function OK   { param($m) Write-Host "[OK]  $m" -ForegroundColor Green }
function WARN { param($m) Write-Host "[!]   $m" -ForegroundColor Yellow }
function ERR  { param($m) Write-Host "[ERR] $m" -ForegroundColor Red; exit 1 }

Log "=== Instalador NodeODM para Windows 11 ==="

# ── Verificar Ubuntu de forma segura ──────────────────────────────────────
$ubuntuInstalado = $null
try {
    $ubuntuInstalado = (wsl --list --quiet 2>&1) | Where-Object { $_ -match "Ubuntu" }
} catch { $ubuntuInstalado = $null }

$tareaInicio = Get-ScheduledTask -TaskName $TAREA_INICIO -ErrorAction SilentlyContinue

# ── Si ya está instalado: arrancar ────────────────────────────────────────
if ($ubuntuInstalado -and $tareaInicio) {
    Log "NodeODM ya instalado. Iniciando..."
    wsl -d Ubuntu -u root -- bash -c "systemctl start docker 2>/dev/null || service docker start 2>/dev/null; sleep 5; docker start nodeodm 2>/dev/null || docker run -d --name nodeodm --restart always -p 3000:3000 opendronemap/nodeodm"
    OK "NodeODM corriendo en puerto 3000"
    exit 0
}

# ── Copiar bash script (CRLF -> LF) ──────────────────────────────────────
$bashSrc = Join-Path $PSScriptRoot "instalar_nodeodm.sh"
if (-not (Test-Path $bashSrc)) {
    ERR "No se encontró 'instalar_nodeodm.sh' junto a este script."
}

New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
$contenido = Get-Content $bashSrc -Raw
$contenido = $contenido -replace "`r`n", "`n"
[System.IO.File]::WriteAllText(
    "$INSTALL_DIR\instalar_nodeodm.sh",
    $contenido,
    [System.Text.Encoding]::UTF8
)
OK "Script bash copiado a $INSTALL_DIR"

# ── Configurar .wslconfig (Windows) ──────────────────────────────────────
# networkingMode=mirrored: WSL2 usa la misma IP que Windows (sin port proxy)
# vmIdleTimeout=-1: evita que la VM se apague sola (crítico para servidor)
$wslConfig = "$env:USERPROFILE\.wslconfig"
Set-Content -Path $wslConfig -Value "[wsl2]`nnetworkingMode=mirrored`nvmIdleTimeout=-1`n" -Encoding UTF8
OK ".wslconfig configurado (mirrored + vmIdleTimeout=-1)"

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
    Log "Instalando Ubuntu en WSL2 (puede tardar varios minutos)..."
    wsl --set-default-version 2 2>$null
    wsl --install -d Ubuntu --web-download --no-launch
    OK "Ubuntu instalado en WSL2"
} else {
    OK "Ubuntu ya instalado en WSL2"
}

# ── Firewall: puerto 3000 (NodeODM) ──────────────────────────────────────
if (-not (Get-NetFirewallRule -DisplayName "NodeODM-3000" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "NodeODM-3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow | Out-Null
    OK "Firewall: puerto 3000 TCP abierto"
} else {
    OK "Firewall: regla para puerto 3000 ya existe"
}

# ── WSL-KeepAlive: mantiene la VM de WSL2 activa permanentemente ──────────
# Sin esto, WSL2 apaga la VM cuando no hay comandos activos, tirando abajo
# NodeODM y Docker en crash loops. LogonType S4U sobrevive reconexiones RDP.
$accionKA = New-ScheduledTaskAction `
    -Execute "wsl.exe" `
    -Argument "-d Ubuntu -u root -- bash -c `"while true; do sleep 3600; done`""
$disparadoresKA = @(
    (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME),
    (New-ScheduledTaskTrigger -AtStartup)
)
$configKA = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RunOnlyIfNetworkAvailable:$false `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1)
$principalKA = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest

Register-ScheduledTask `
    -TaskName $TAREA_KEEPALIVE `
    -Action $accionKA `
    -Trigger $disparadoresKA `
    -Settings $configKA `
    -Principal $principalKA `
    -Force | Out-Null
OK "Tarea '$TAREA_KEEPALIVE' creada (mantiene WSL2 activo)"

# ── Tarea Fase 2: corre bash al volver a iniciar sesión ──────────────────
$accion2    = New-ScheduledTaskAction `
    -Execute "wsl.exe" `
    -Argument "-d Ubuntu -u root -- bash /mnt/c/webodm_install/instalar_nodeodm.sh"
$disparador2 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$config2     = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -RunOnlyIfNetworkAvailable:$false
$principal2  = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest

Register-ScheduledTask `
    -TaskName $TAREA_FASE2 `
    -Action $accion2 `
    -Trigger $disparador2 `
    -Settings $config2 `
    -Principal $principal2 `
    -Force | Out-Null
OK "Tarea '$TAREA_FASE2' creada: instalará Docker + NodeODM al reiniciar"

# ── Reinicio o ejecución directa ─────────────────────────────────────────
if ($necesitaReinicio) {
    Write-Host ""
    WARN "Reinicio necesario para activar WSL2."
    WARN "Al volver a iniciar sesión, Docker + NodeODM se instalan solos."
    WARN "El proceso tarda 5-10 minutos la primera vez (descarga imagen Docker)."
    Write-Host ""
    $r = Read-Host "Reiniciar ahora? (s/n)"
    if ($r -eq "s") {
        Restart-Computer -Force
    } else {
        WARN "Reinicia manualmente cuando puedas."
    }
} else {
    Log "WSL2 ya activo. Ejecutando instalación directamente..."
    Start-ScheduledTask -TaskName $TAREA_KEEPALIVE
    wsl -d Ubuntu -u root -- bash /mnt/c/webodm_install/instalar_nodeodm.sh
}
