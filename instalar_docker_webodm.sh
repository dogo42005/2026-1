#!/bin/bash
# instalar_docker_webodm.sh
# FASE 2: Instala Docker Engine + WebODM dentro de WSL2 Ubuntu
# Ejecutado automáticamente por tarea programada de Windows después del reinicio
# Corre como root (-u root), no requiere intervención manual

set -e

WEBODM_DIR="$HOME/WebODM"
WEBODM_PORT=8000
LOG_FILE="/var/log/webodm_install.log"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
ok()  { echo "[OK]  $1" | tee -a "$LOG_FILE"; }

exec > >(tee -a "$LOG_FILE") 2>&1   # Redirigir todo al log

log "=== Instalación Docker Engine + WebODM ==="
log "Directorio destino: $WEBODM_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# Actualizar repositorios e instalar dependencias base
# ─────────────────────────────────────────────────────────────────────────────
log "Actualizando repositorios..."
apt-get update -y -qq

log "Instalando dependencias..."
apt-get install -y -qq ca-certificates curl gnupg git
ok "Dependencias base instaladas"

# ─────────────────────────────────────────────────────────────────────────────
# Agregar repositorio oficial de Docker (solo si no existe)
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    log "Configurando repositorio oficial Docker..."
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

# ─────────────────────────────────────────────────────────────────────────────
# Instalar Docker Engine (sin Docker Desktop, sin GUI, sin EULA)
# ─────────────────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log "Instalando Docker Engine..."
    apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    ok "Docker Engine instalado"
else
    ok "Docker Engine ya estaba instalado"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Arrancar Docker daemon
# WSL2 sin systemd: usar service (init.d) o dockerd directo como fallback
# ─────────────────────────────────────────────────────────────────────────────
log "Iniciando Docker daemon..."
if ! service docker start 2>/dev/null; then
    log "service no disponible, iniciando dockerd directamente..."
    nohup dockerd > /var/log/dockerd.log 2>&1 &
fi

# Esperar hasta que Docker responda (máximo 30 segundos)
for i in $(seq 1 10); do
    if docker info &>/dev/null; then
        break
    fi
    log "Esperando Docker daemon... ($i/10)"
    sleep 3
done

docker --version
ok "Docker daemon activo"

# ─────────────────────────────────────────────────────────────────────────────
# Clonar WebODM (o actualizar si ya existe)
# ─────────────────────────────────────────────────────────────────────────────
if [ -d "$WEBODM_DIR/.git" ]; then
    log "WebODM ya clonado, actualizando..."
    git -C "$WEBODM_DIR" pull --quiet
    ok "WebODM actualizado"
else
    log "Clonando WebODM desde GitHub..."
    git clone --quiet https://github.com/OpenDroneMap/WebODM.git "$WEBODM_DIR"
    ok "WebODM clonado en $WEBODM_DIR"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Iniciar WebODM
# La primera vez descarga imágenes Docker (~1-2 GB), puede tardar 5-15 min
# Las siguientes veces arranca en ~30 segundos
# ─────────────────────────────────────────────────────────────────────────────
cd "$WEBODM_DIR"
log "Iniciando WebODM en puerto $WEBODM_PORT..."
log "(Primera vez: descarga imágenes Docker, esperar 5-15 minutos)"
./webodm.sh start --port $WEBODM_PORT
ok "WebODM corriendo"

# ─────────────────────────────────────────────────────────────────────────────
# Crear tarea programada de Windows para arranque automático en futuros reinicios
# ─────────────────────────────────────────────────────────────────────────────
log "Configurando inicio automático de WebODM para próximos reinicios..."

# Llamar a PowerShell desde WSL2 para crear la tarea programada en Windows
powershell.exe -NonInteractive -Command "
    \$a = New-ScheduledTaskAction \`
        -Execute 'wsl.exe' \`
        -Argument '-d Ubuntu -u root -- bash -c \"service docker start 2>/dev/null || nohup dockerd > /var/log/dockerd.log 2>&1 & sleep 10; cd ~/WebODM && ./webodm.sh start --port 8000\"'
    \$t = New-ScheduledTaskTrigger -AtLogOn -User \$env:USERNAME
    \$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -RunOnlyIfNetworkAvailable \$false
    \$p = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -RunLevel Highest
    Register-ScheduledTask -TaskName 'WebODM-Autostart' -Action \$a -Trigger \$t -Settings \$s -Principal \$p -Force | Out-Null
    Unregister-ScheduledTask -TaskName 'WebODM-Instalacion-Fase2' -Confirm:\$false -ErrorAction SilentlyContinue
" 2>/dev/null && ok "Tarea de inicio automático creada en Windows" || true

# ─────────────────────────────────────────────────────────────────────────────
# Obtener IP del servidor (con red espejo WSL2 = misma IP que Windows)
# ─────────────────────────────────────────────────────────────────────────────
IP_SERVIDOR=$(ip route get 1 2>/dev/null | awk '{print $NF; exit}' || hostname -I | awk '{print $1}')

log ""
log "=========================================="
log "   INSTALACIÓN COMPLETADA"
log "=========================================="
log "WebODM accesible en: http://${IP_SERVIDOR}:${WEBODM_PORT}"
log ""
log "Primer acceso:"
log "  1. Abrir http://${IP_SERVIDOR}:${WEBODM_PORT} en el navegador"
log "  2. Crear cuenta de administrador"
log "  3. Usar esas credenciales en config_remoto.json"
log ""
log "Log de instalación guardado en: $LOG_FILE"
log "=========================================="
