#!/bin/bash
# instalar_nodeodm.sh
# FASE 2: Instala Docker Engine + NodeODM dentro de WSL2 Ubuntu
# Ejecutado automáticamente por tarea programada de Windows después del reinicio
# Corre como root (-u root), no requiere intervención manual

set -e

LOG_FILE="/var/log/nodeodm_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $1"; }
ok()  { echo "[OK]  $1"; }

log "=== Instalación Docker Engine + NodeODM ==="

# ── Habilitar systemd en WSL2 ─────────────────────────────────────────────
# Requerido para que Docker persista entre sesiones sin crash loop.
# Activo desde el PRÓXIMO reinicio de WSL2 (esta sesión corre sin él).
printf '[boot]\nsystemd=true\n' > /etc/wsl.conf
ok "systemd habilitado en /etc/wsl.conf (activo al reiniciar WSL2)"

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
    ok "Repositorio Docker configurado"
fi

# ── Docker Engine ─────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log "Instalando Docker Engine..."
    apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    ok "Docker Engine instalado"
else
    ok "Docker Engine ya instalado"
fi

# Habilitar para futuros boots con systemd
systemctl enable docker 2>/dev/null || true

# ── Arrancar Docker daemon ────────────────────────────────────────────────
# En esta primera ejecución systemd aún no está activo.
log "Iniciando Docker daemon..."
if ! service docker start 2>/dev/null; then
    log "service no disponible, iniciando dockerd directamente..."
    nohup dockerd > /var/log/dockerd.log 2>&1 &
fi

for i in $(seq 1 10); do
    docker info &>/dev/null && break
    log "Esperando Docker daemon... ($i/10)"
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

# ── Tarea Windows: inicio automático en futuros reinicios ────────────────
log "Configurando inicio automático..."
powershell.exe -NonInteractive -Command "
    \$a = New-ScheduledTaskAction \`
        -Execute 'wsl.exe' \`
        -Argument '-d Ubuntu -u root -- bash -c \"systemctl start docker 2>/dev/null || service docker start 2>/dev/null; sleep 8; docker start nodeodm\"'
    \$t = New-ScheduledTaskTrigger -AtLogOn -User \$env:USERNAME
    \$s = New-ScheduledTaskSettingsSet \`
        -ExecutionTimeLimit ([TimeSpan]::Zero) \`
        -RunOnlyIfNetworkAvailable:\$false
    \$p = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -RunLevel Highest
    Register-ScheduledTask -TaskName 'NodeODM-Autostart' -Action \$a -Trigger \$t -Settings \$s -Principal \$p -Force | Out-Null
    Unregister-ScheduledTask -TaskName 'NodeODM-Instalacion-Fase2' -Confirm:\$false -ErrorAction SilentlyContinue
" 2>/dev/null && ok "Inicio automático configurado" || true

# ── Verificar que responde ────────────────────────────────────────────────
log "Verificando NodeODM (esperar 15 segundos)..."
sleep 15
ESTADO=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 || echo "000")
if [ "$ESTADO" = "200" ]; then
    ok "NodeODM responde correctamente (HTTP 200)"
else
    log "AVISO: NodeODM devolvió HTTP $ESTADO. Puede estar iniciándose aún."
    log "Verificar en 1-2 minutos: curl http://localhost:3000"
fi

# ── Resultado final ───────────────────────────────────────────────────────
IP=$(ip route get 1 2>/dev/null | awk '{print $NF; exit}' || hostname -I | awk '{print $1}')

log ""
log "=========================================="
log "   NODEODM LISTO"
log "=========================================="
log "NodeODM escuchando en: http://${IP}:3000"
log ""
log "Agregar en WebODM maestro:"
log "  Nodos de procesamiento → Agregar nuevo"
log "  Nombre de host: ${IP}"
log "  Puerto: 3000"
log "  Token: (dejar vacío)"
log ""
log "Log: $LOG_FILE"
log "=========================================="
