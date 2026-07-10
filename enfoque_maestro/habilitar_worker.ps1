#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Prepara un PC para actuar como trabajador en la red WebODM.
    Ejecutar UNA SOLA VEZ en cada PC trabajador como Administrador.

    Hace tres cosas:
      1. Habilita PowerShell Remoting (WinRM) para recibir comandos del maestro
      2. Abre el puerto de WinRM en el firewall de Windows
      3. Verifica que Python y el pipeline estén instalados
#>

$ErrorActionPreference = "Stop"

function Log  { param($m) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $m" -ForegroundColor Cyan }
function OK   { param($m) Write-Host "[OK]  $m" -ForegroundColor Green }
function WARN { param($m) Write-Host "[!]   $m" -ForegroundColor Yellow }

Log "=== Habilitando PC como Worker WebODM ==="

# ── Habilitar PowerShell Remoting (WinRM) ─────────────────────────────────
Log "Habilitando PowerShell Remoting..."
Enable-PSRemoting -Force -SkipNetworkProfileCheck
OK "PowerShell Remoting habilitado"

# ── Configurar WinRM para aceptar conexiones ──────────────────────────────
Log "Configurando WinRM..."
Set-Item WSMan:\localhost\Client\AllowUnencrypted -Value $true  -Force
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true       -Force
Restart-Service WinRM
OK "WinRM configurado"

# ── Regla de firewall para WinRM (puerto 5985) ────────────────────────────
if (-not (Get-NetFirewallRule -DisplayName "WinRM-Worker" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -DisplayName "WinRM-Worker" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 5985 `
        -Action Allow | Out-Null
    OK "Firewall: puerto WinRM (5985) abierto"
} else {
    OK "Firewall: regla WinRM ya existe"
}

# ── Verificar Python ──────────────────────────────────────────────────────
if (Get-Command python -ErrorAction SilentlyContinue) {
    $ver = python --version
    OK "Python instalado: $ver"
} else {
    WARN "Python no encontrado. Instalando..."
    winget install Python.Python.3.11 --silent
    OK "Python instalado. Reinicia PowerShell para usar el comando python."
}

# ── Verificar pipeline ────────────────────────────────────────────────────
$pipelinePath = "C:\webodm_install\webodm_pipeline.py"
if (Test-Path $pipelinePath) {
    OK "Pipeline encontrado: $pipelinePath"
} else {
    WARN "Pipeline NO encontrado en $pipelinePath"
    WARN "Copia webodm_pipeline.py y config.json a C:\webodm_install\ antes de usar este PC como worker"
}

# ── Mostrar IP del PC para agregar al config_maestro.json ─────────────────
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch "127\." -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1).IPAddress

Write-Host ""
Log "=== WORKER LISTO ==="
OK "IP de este PC: $ip"
Write-Host ""
Write-Host "  Agrega esta entrada al config_maestro.json del PC maestro:" -ForegroundColor Yellow
Write-Host @"
  {
    "nombre": "Worker-$(hostname)",
    "ip": "$ip",
    "usuario": "$(whoami -split '\\' | Select-Object -Last 1)",
    "password": "TU_CONTRASEÑA_AQUI",
    "images_dir": "RUTA\\A\\TUS\\FOTOS",
    "pipeline": "C:\\webodm_install\\webodm_pipeline.py",
    "config":   "C:\\webodm_install\\config.json"
  }
"@ -ForegroundColor Gray
