#!/bin/bash
# instalar_nodeodm.sh
# Instala Docker Engine + NodeODM dentro de WSL2 Ubuntu
# Más liviano que WebODM completo — solo el motor de procesamiento

set -e

LOG_FILE="/var/log/nodeodm_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $1"; }
ok()  { echo "[OK]  $1"; }

log "=== Instalación Docker Engine + NodeODM ==="

# ── Dependencias base ─────────────────────────────────────────────────────
log "Actualizando repositorios..."
apt-get update -y -qq
apt-get install -y -qq ca-certificates curl gnupg
ok "Dependencias instaladas"

# ── Repositorio oficial Docker ────────────────────────────────────────────
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    log "Configurando repositorio Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y -qq
fi

# ── Docker Engine ─────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log "Instalando Docker Engine..."
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ok "Docker Engine instalado"
else
    ok "Docker Engine ya instalado"
fi

# ── Arrancar Docker daemon ────────────────────────────────────────────────
log "Iniciando Docker daemon..."
service docker start 2>/dev/null || nohup dockerd > /var/log/dockerd.log 2>&1 &
for i in $(seq 1 10); do
    docker info &>/dev/null && break
    sleep 3
done
docker --version
ok "Docker daemon activo"

# ── NodeODM ───────────────────────────────────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -q "^nodeodm$"; then
    log "Contenedor nodeodm ya existe, iniciando..."
    docker start nodeodm
else
    log "Descargando e iniciando NodeODM..."
    docker run -d \
        --name nodeodm \
        --restart always \
        -p 3000:3000 \
        opendronemap/nodeodm
fi
ok "NodeODM corriendo en puerto 3000"

# ── Tarea de inicio automático en Windows ────────────────────────────────
log "Configurando inicio automático..."
powershell.exe -NonInteractive -Command "
    \$a = New-ScheduledTaskAction \`
        -Execute 'wsl.exe' \`
        -Argument '-d Ubuntu -u root -- bash -c \"service docker start 2>/dev/null || nohup dockerd > /var/log/dockerd.log 2>&1 & sleep 8; docker start nodeodm\"'
    \$t = New-ScheduledTaskTrigger -AtLogOn -User \$env:USERNAME
    \$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -RunOnlyIfNetworkAvailable:\$false
    \$p = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -RunLevel Highest
    Register-ScheduledTask -TaskName 'NodeODM-Autostart' -Action \$a -Trigger \$t -Settings \$s -Principal \$p -Force | Out-Null
    Unregister-ScheduledTask -TaskName 'NodeODM-Instalacion-Fase2' -Confirm:\$false -ErrorAction SilentlyContinue
" 2>/dev/null && ok "Inicio automático configurado" || true

IP=$(ip route get 1 2>/dev/null | awk '{print $NF; exit}' || hostname -I | awk '{print $1}')

log ""
log "=========================================="
log "   NODEODM LISTO"
log "=========================================="
log "NodeODM escuchando en: http://${IP}:3000"
log ""
log "Agregar en WebODM maestro (146.155.38.81:8000):"
log "  Nodos de procesamiento → Agregar nuevo"
log "  Nombre de host: ${IP}"
log "  Puerto: 3000"
log "  Token: (dejar vacío)"
log "=========================================="
