# Contexto del proyecto — Red de procesamiento fotogramétrico
## IPRE IPI-26-704 — Diego Olivares, PUC

---

## Arquitectura objetivo

```
PC Maestro (.80 — 146.155.38.80)  ←── WebODM (puerto 8000)
    ├── PC-81 (146.155.38.81:3000) ←── NodeODM worker
    └── PC-82 (146.155.38.82:3000) ←── NodeODM worker
```

- **WebODM**: interfaz web + orquestador de tareas fotogramétricas
- **NodeODM**: motor de procesamiento (recibe tareas del maestro)
- Las fotos están en Google Drive, accesible desde todos los PCs:
  `G:\Mi unidad\03.- PUC\06.- 2026\02.- Estudiantes\06.- DOP\2026-1\FOTOS\`

---

## Estado actual de cada PC

### PC .80 (146.155.38.80) — WEBODM INSTALADO Y CORRIENDO ✓ (falta cuenta + verificación externa)
- Windows 11, WSL2 con Ubuntu, systemd habilitado, Docker Engine funcionando con systemd
- Contenedor `nodeodm` viejo **eliminado**
- WebODM clonado y corriendo con `--default-nodes 0` (contenedores `webapp`, `worker`, `broker`, `db` — todos estables)
- Firewall puerto 8000 abierto (`WebODM-8000`)
- `networkingMode=mirrored` funcionando correctamente: **no hace falta port proxy** en este PC (ver sección "Mirrored networking" más abajo)
- Se detectó y arregló un bug grave: la VM de WSL2 se apagaba sola por inactividad, tirando abajo WebODM constantemente (ver sección "Problema: apagado automático de la VM WSL2")
- `http://localhost:8000` responde **200/302** de forma estable
- **Pendiente:**
  - Crear cuenta de administrador (se cayó una vez a mitad del login por el bug de la VM, ya resuelto — falta reintentar y confirmar)
  - Confirmar acceso desde `http://146.155.38.80:8000` **desde otro dispositivo** (probar desde el propio .80 da falso negativo por hairpin NAT)
  - Agregar nodos .81 y .82 una vez estén listos

### PC .81 (146.155.38.81) — CONVERTIR A NODEODM WORKER
- Windows 11, WSL2 con Ubuntu + systemd
- Docker Engine + WebODM instalado (corriendo con problemas)
- WebODM tiene un bug: `node-odx-1` (nodo interno) crashea en loop,
  bloqueando el arranque de nginx/gunicorn con `python manage.py addnode`
- **Tarea: bajar WebODM, instalar NodeODM worker, port proxy puerto 3000**

### PC .82 (146.155.38.82) — NODEODM WORKER (parcialmente listo)
- Windows 11, WSL2 con Ubuntu + systemd
- Docker Engine + contenedor `nodeodm` instalado
- NodeODM sigue en crash loop (mismo síntoma que antes del fix de systemd)
- Port proxy configurado pero se pierde al reiniciar
- **Tarea: diagnosticar crash loop de NodeODM, hacer port proxy permanente**

---

## Contexto técnico clave

### Por qué Docker Engine en WSL2 (no Docker Desktop)
- Docker Desktop requiere aceptar EULA interactiva — no apto para instalación remota/automatizada
- Solución: Docker Engine instalado dentro de WSL2 Ubuntu via apt

### Problema del crash loop de NodeODM
Síntoma en `docker logs nodeodm`:
```
info: Server has started on port 3000
info: Closing server
info: Exiting...
```
Se repite indefinidamente. Causa: Docker daemon no persiste sin systemd en WSL2.

Fix aplicado (en .80 y .82):
```powershell
# Habilitar systemd en WSL2
wsl -d Ubuntu -u root -- bash -c "printf '[boot]\nsystemd=true\n' > /etc/wsl.conf"
# Configurar red en modo espejo (archivo Windows)
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value "[wsl2]`nnetworkingMode=mirrored`n" -Encoding UTF8
wsl --shutdown
# Esperar 15 segundos, luego:
wsl -d Ubuntu -u root -- bash -c "systemctl enable docker && systemctl start docker && sleep 5 && docker start nodeodm"
```

### Port proxy (necesario solo si networkingMode=mirrored no propaga el puerto)
```powershell
$wslIp = (wsl -d Ubuntu hostname -I).Trim().Split(' ')[0]
netsh interface portproxy add v4tov4 listenport=3000 listenaddress=0.0.0.0 connectport=3000 connectaddress=$wslIp
```

Para que sobreviva reinicios (la IP de WSL2 cambia cada vez):
```powershell
$wslIp2 = "(wsl -d Ubuntu hostname -I).Trim().Split(' ')[0]"
$cmd = "& { `$ip = $wslIp2; netsh interface portproxy delete v4tov4 listenport=3000 listenaddress=0.0.0.0; netsh interface portproxy add v4tov4 listenport=3000 listenaddress=0.0.0.0 connectport=3000 connectaddress=`$ip }"
$a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NonInteractive -Command `"$cmd`""
$t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
Register-ScheduledTask -TaskName "NodeODM-PortProxy" -Action $a -Trigger $t -Settings (New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable:$false) -Principal $p -Force | Out-Null
```

**⚠️ Aprendizaje del .80 (aplicable a .81/.82):** el motivo original por el que se pensó que "mirrored no propaga el puerto" era probablemente el mismo bug de `/etc/wsl.conf` (ver más abajo) — con `networkingMode=mirrored` puesto en el archivo equivocado, WSL2 caía a modo NAT normal sin avisar, y ahí sí hacía falta port proxy. En el .80, una vez corregido `/etc/wsl.conf` y confirmado el modo mirrored real (`ip addr` dentro de WSL muestra la IP pública del PC directamente en `eth0`), **el puerto quedó expuesto sin necesidad de port proxy** — de hecho, agregar un port proxy en paralelo causó conflicto (bloqueaba el acceso por la IP externa aunque `localhost` seguía funcionando) y hubo que eliminarlo. Antes de configurar port proxy en .81/.82, verificar primero si mirrored ya funciona solo.

### Problema: apagado automático de la VM de WSL2 (crítico — causaba caídas intermitentes en .80)

**Síntoma:** `docker ps` siempre mostraba los contenedores de WebODM con muy poco tiempo de actividad ("Up 3 segundos", "Up 4 segundos"), sin importar cuánto tiempo hubiera pasado entre chequeos. `RestartCount` de los contenedores se mantenía en `0` (no eran los contenedores reiniciándose — era **toda la VM de WSL2 apagándose y volviendo a arrancar**). Esto causaba que `http://localhost:8000` a veces respondiera `000` (sin conexión) o que el login se cortara a mitad de camino.

**Causa:** WSL2 apaga su VM automáticamente cuando no hay ningún proceso `wsl.exe` conectado (comportamiento por defecto, pensado para no consumir recursos en equipos de escritorio normales — pero rompe cualquier uso como "servidor siempre encendido"). Cada invocación de `wsl -d Ubuntu -- comando` desde PowerShell se conecta, ejecuta, y se desconecta; si nada más queda conectado, Windows apaga la VM a los pocos segundos.

**Fix (2 partes, ambas necesarias):**

1. `vmIdleTimeout=-1` en `.wslconfig` (mitiga pero no fue suficiente por sí solo):
```powershell
# .wslconfig debe quedar:
# [wsl2]
# networkingMode=mirrored
# vmIdleTimeout=-1
```

2. Tarea programada que mantiene una sesión de WSL2 enganchada permanentemente en segundo plano (esto sí resolvió el problema). Importante usar `-LogonType S4U` y no el logon interactivo por defecto — la primera versión de esta tarea usaba logon atado a la sesión activa, y se murió (`LastTaskResult: 3221225786` = proceso terminado junto con la sesión) apenas hubo una reconexión/renovación de sesión RDP:
```powershell
$accion = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -u root -- bash -c `"while true; do sleep 3600; done`""
$disparador1 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$disparador2 = New-ScheduledTaskTrigger -AtStartup
$config = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RunOnlyIfNetworkAvailable:$false -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest
Register-ScheduledTask -TaskName "WSL-KeepAlive" -Action $accion -Trigger @($disparador1,$disparador2) -Settings $config -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName "WSL-KeepAlive"
```

Verificar que sigue viva y que el uptime de los contenedores realmente sube entre chequeos (no se resetea a "Up X segundos" cada vez):
```powershell
Get-ScheduledTask -TaskName "WSL-KeepAlive" | Get-ScheduledTaskInfo   # LastTaskResult 267009 = "en ejecución", correcto
Get-Process wsl* | Select-Object Id, ProcessName, StartTime           # debe haber un proceso wsl.exe vivo
wsl -d Ubuntu -u root -- docker ps --format "table {{.Names}}\t{{.Status}}"
```

**Aplica también a .81 y .82** — cualquier PC que corra WebODM o NodeODM como servidor permanente necesita este mismo fix, si no los contenedores se van a reiniciar cada vez que nadie esté ejecutando comandos de `wsl` activamente.

### Problema de WebODM en .81 (por qué no arranca)
El contenedor `webapp` se queda bloqueado en:
```
python manage.py addnode node-odx-1 3000 --label node-odx-1
```
con 714% CPU porque `node-odx-1` (el nodo interno de WebODM) también está en crash loop.
Solución usada: `--default-nodes 0` para omitir el nodo interno.

### Archivos de scripts disponibles (en el repo del proyecto)
| Archivo | Descripción |
|---|---|
| `instalar_webodm.ps1` | Fase 1: habilita WSL2, instala Ubuntu, programa Fase 2 |
| `instalar_docker_webodm.sh` | Fase 2: instala Docker + WebODM dentro de WSL2 |
| `instalar_nodeodm.ps1` | Fase 1: habilita WSL2 para PCs worker |
| `instalar_nodeodm.sh` | Fase 2: instala Docker + NodeODM dentro de WSL2 |
| `webodm_pipeline.py` | Script Python para subir fotos y lanzar procesamiento |
| `config.json` | Config WebODM local (localhost:8000) |
| `config_remoto.json` | Config WebODM remoto (146.155.38.80:8000) — actualizar IP |

---

## Tareas pendientes por PC

### En el .80 — COMPLETADO salvo lo marcado

1. ✓ **`/etc/wsl.conf` corregido** — tenía `[wsl2] networkingMode=mirrored` puesto por error junto con `[boot] systemd=true` (WSL tiraba `Unknown key 'wsl2.networkingMode'`). Se dejó solo:
```
[boot]
systemd=true
```
`networkingMode=mirrored` va en `C:\Users\<usuario>\.wslconfig` (Windows), no ahí.

2. ✓ **NodeODM viejo eliminado y WebODM clonado/corriendo:**
```powershell
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm 2>/dev/null; docker rm nodeodm 2>/dev/null; cd ~ && git clone https://github.com/OpenDroneMap/WebODM --config core.autocrlf=input -b master && cd WebODM && ./webodm.sh start --port 8000 --detach --default-nodes 0"
```

3. ✓ **Firewall puerto 8000 abierto:**
```powershell
New-NetFirewallRule -DisplayName "WebODM-8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
```

4. ✓ **Port proxy: NO se necesitó** — mirrored networking expone el puerto directamente. Se había agregado uno al puerto 8000 por error (redundante) y se eliminó porque bloqueaba el acceso externo:
```powershell
netsh interface portproxy delete v4tov4 listenport=8000 listenaddress=0.0.0.0
```

5. ✓ **Tarea `WSL-KeepAlive` creada** (ver sección "Problema: apagado automático de la VM de WSL2") — sin esto WebODM se caía solo cada pocos minutos.

6. ✓ **Verificado que responde:**
```powershell
curl.exe -s -o NUL -w "%{http_code}" http://localhost:8000     # → 302
curl.exe -s -o NUL -w "%{http_code}" http://localhost:8000/welcome/  # → 200
```

7. **⏳ PENDIENTE — Crear cuenta** en `http://localhost:8000`. Se intentó una vez pero la página se cayó a mitad del login (causado por el bug de apagado de VM, ya resuelto) — falta reintentar.

8. **⏳ PENDIENTE — Confirmar acceso externo real.** Probar `http://146.155.38.80:8000` **desde otro dispositivo en la misma red** (celular, otra laptop). Probarlo desde el propio .80 da `000` por hairpin NAT (una máquina no siempre puede alcanzarse a sí misma por su IP pública/LAN) — eso NO significa que esté roto para otros PCs.

9. **PENDIENTE — Agregar nodos** en WebODM → Nodos de procesamiento → Agregar (recién cuando .81/.82 estén listos):
   - Host: `146.155.38.81`, Puerto: `3000`, Etiqueta: `PC-81`
   - Host: `146.155.38.82`, Puerto: `3000`, Etiqueta: `PC-82`

### En el .81 — hacer después

1. Bajar WebODM:
```powershell
wsl -d Ubuntu -u root -- bash -c "cd ~/WebODM && ./webodm.sh down"
```

2. Instalar NodeODM:
```powershell
wsl -d Ubuntu -u root -- bash -c "docker run -d --name nodeodm --restart always -p 3000:3000 opendronemap/nodeodm"
```

3. Abrir firewall puerto 3000 y aplicar port proxy (igual que .82).

### En el .82 — diagnosticar crash loop

El nodeodm sigue en crash loop a pesar del fix de systemd. Systemd sí está activo.
Verificar con:
```powershell
wsl -d Ubuntu -u root -- docker logs nodeodm --tail 20
```
Intentar en modo test para aislar el problema:
```powershell
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm && docker rm nodeodm && docker run -d --name nodeodm --restart always -p 3000:3000 opendronemap/nodeodm --test && sleep 10 && curl -s -o /dev/null -w '%{http_code}' http://localhost:3000"
```

---

## Comandos de diagnóstico frecuentes

```powershell
# Ver contenedores corriendo
wsl -d Ubuntu -u root -- docker ps

# Ver logs de WebODM (sin ruido)
wsl -d Ubuntu -u root -- bash -c "docker logs webapp 2>&1 | grep -v 'Booting worker' | tail -40"

# Ver logs de NodeODM
wsl -d Ubuntu -u root -- docker logs nodeodm --tail 20

# Verificar que WebODM responde
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8000

# Verificar que NodeODM responde
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:3000

# Estado de Docker con systemd
wsl -d Ubuntu -u root -- systemctl status docker --no-pager

# Ver port proxies configurados
netsh interface portproxy show all

# Ver contenido actual de /etc/wsl.conf (Linux) y .wslconfig (Windows) — no deben mezclarse
wsl -d Ubuntu -u root -- cat /etc/wsl.conf
Get-Content "$env:USERPROFILE\.wslconfig"

# Verificar que la VM de WSL2 no se está reiniciando sola (el uptime debe subir entre chequeos, no resetearse)
wsl -d Ubuntu -u root -- docker ps --format "table {{.Names}}\t{{.Status}}"

# Verificar que la tarea de keep-alive sigue viva
Get-ScheduledTask -TaskName "WSL-KeepAlive" | Get-ScheduledTaskInfo
Get-Process wsl* | Select-Object Id, ProcessName, StartTime

# Confirmar modo mirrored real dentro de WSL (debe mostrar la IP pública del PC, no 172.x)
wsl -d Ubuntu -u root -- ip -4 addr show eth0

# Reiniciar WebODM manualmente
wsl -d Ubuntu -u root -- bash -c "cd ~/WebODM && ./webodm.sh start --port 8000 --detach --default-nodes 0"

# Iniciar NodeODM manualmente
wsl -d Ubuntu -u root -- bash -c "systemctl start docker && sleep 5 && docker start nodeodm"
```

---

## Cómo ejecutar el pipeline

Desde cualquier PC con Python y acceso al Google Drive, apuntando al maestro (.80):

```powershell
python webodm_pipeline.py --config config_remoto.json --preset "Fast Orthophoto" --images "G:\Mi unidad\03.- PUC\06.- 2026\02.- Estudiantes\06.- DOP\2026-1\FOTOS\03.- Edificio Raúl Deves"
```

> **Nota:** actualizar `config_remoto.json` para que apunte a `http://146.155.38.80:8000`

---

## Notas importantes

- `networkingMode=mirrored` debe estar en `C:\Users\<usuario>\.wslconfig` (Windows), NO en `/etc/wsl.conf` (Linux)
- `/etc/wsl.conf` solo debe tener `[boot]\nsystemd=true`
- El port proxy usa la IP interna de WSL2 (`hostname -I`) que cambia con cada reinicio — por eso la tarea programada la recalcula al iniciar sesión
- WebODM tarda 2-3 minutos en arrancar completamente después de `docker compose up`
- Con `--default-nodes 0` WebODM no intenta registrar el nodo interno `node-odx-1`
