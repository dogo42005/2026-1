#!/bin/bash
# instalar_docker_webodm.sh
# FASE 2: Instala Docker Engine + WebODM dentro de WSL2 Ubuntu
# Ejecutado automáticamente por tarea programada de Windows después del reinicio
# Corre como root (-u root), no requiere intervención manual

set -e

WEBODM_DIR="$HOME/WebODM"
WEBODM_PORT=8000
LOG_FILE="/var/log/webodm_install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $1"; }
ok()  { echo "[OK]  $1"; }

log "=== Instalación Docker Engine + WebODM ==="
log "Directorio destino: $WEBODM_DIR"

# ── Habilitar systemd en WSL2 ─────────────────────────────────────────────
# Requerido para que Docker persista entre sesiones sin crash loop.
# Activo desde el PRÓXIMO reinicio de WSL2 (esta sesión corre sin él).
printf '[boot]\nsystemd=true\n' > /etc/wsl.conf
ok "systemd habilitado en /etc/wsl.conf (activo al reiniciar WSL2)"

# ── Dependencias base ─────────────────────────────────────────────────────
log "Actualizando repositorios..."
apt-get update -y -qq
apt-get install -y -qq ca-certificates curl gnupg git
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
# service docker start usa init.d; si falla, levanta dockerd directamente.
log "Iniciando Docker daemon..."
if ! service docker start 2>/dev/null; then
    log "service no disponible, iniciando dockerd directamente..."
    nohup dockerd > /var/log/dockerd.log 2>&1 &
fi

for i in $(seq 1 12); do
    docker info &>/dev/null && break
    log "Esperando Docker daemon... ($i/12)"
    sleep 5
done
docker --version
ok "Docker daemon activo"

# ── Clonar o actualizar WebODM ────────────────────────────────────────────
if [ -d "$WEBODM_DIR/.git" ]; then
    log "WebODM ya clonado, actualizando..."
    git -C "$WEBODM_DIR" pull --quiet
    ok "WebODM actualizado"
else
    log "Clonando WebODM desde GitHub..."
    git clone --quiet https://github.com/OpenDroneMap/WebODM.git "$WEBODM_DIR"
    ok "WebODM clonado en $WEBODM_DIR"
fi

# ── Iniciar WebODM ────────────────────────────────────────────────────────
# --default-nodes 0: no registra node-odx-1 interno (evita deadlock al arrancar
#   si el nodo interno cae en crash loop bloqueando manage.py addnode al 714% CPU)
# --detach: regresa control al script inmediatamente (WebODM corre en background)
cd "$WEBODM_DIR"
log "Iniciando WebODM en puerto $WEBODM_PORT..."
log "(Primera vez: descarga imágenes Docker ~2 GB, puede tardar 5-15 minutos)"
./webodm.sh start --port $WEBODM_PORT --default-nodes 0 --detach
ok "WebODM iniciado"

# ── Tarea Windows: inicio automático en futuros reinicios ────────────────
log "Configurando inicio automático..."
powershell.exe -NonInteractive -Command "
    \$a = New-ScheduledTaskAction \`
        -Execute 'wsl.exe' \`
        -Argument '-d Ubuntu -u root -- bash -c \"systemctl start docker 2>/dev/null || service docker start 2>/dev/null; sleep 8; cd ~/WebODM && ./webodm.sh start --port 8000 --default-nodes 0 --detach\"'
    \$t = New-ScheduledTaskTrigger -AtLogOn -User \$env:USERNAME
    \$s = New-ScheduledTaskSettingsSet \`
        -ExecutionTimeLimit ([TimeSpan]::Zero) \`
        -RunOnlyIfNetworkAvailable:\$false
    \$p = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -RunLevel Highest
    Register-ScheduledTask -TaskName 'WebODM-Autostart' -Action \$a -Trigger \$t -Settings \$s -Principal \$p -Force | Out-Null
    Unregister-ScheduledTask -TaskName 'WebODM-Instalacion-Fase2' -Confirm:\$false -ErrorAction SilentlyContinue
" 2>/dev/null && ok "Inicio automático configurado" || true

# ── Resultado final ───────────────────────────────────────────────────────
IP=$(ip route get 1 2>/dev/null | awk '{print $NF; exit}' || hostname -I | awk '{print $1}')

log ""
log "=========================================="
log "   WEBODM LISTO"
log "=========================================="
log "Acceder en: http://${IP}:${WEBODM_PORT}"
log ""
log "Primer acceso:"
log "  1. Abrir http://${IP}:${WEBODM_PORT} en el navegador"
log "  2. Crear cuenta de administrador"
log "  3. Nodos de procesamiento → Agregar nuevo → IP_NODO:3000"
log ""
log "NOTA: Si el pipeline se ejecuta desde ESTE mismo PC,"
log "  usar config.json (localhost:8000), NO config_remoto.json."
log "  Esto evita el problema de 'hairpin NAT' donde la máquina"
log "  no puede alcanzarse a sí misma por su propia IP de red."
log ""
log "Log: $LOG_FILE"
log "=========================================="
