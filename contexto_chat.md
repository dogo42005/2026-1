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

### PC .80 (146.155.38.80) — INSTALAR WEBODM AQUÍ
- Windows 11, WSL2 con Ubuntu instalado, systemd habilitado
- Docker Engine instalado y funcionando con systemd
- Tiene contenedor `nodeodm` (debe eliminarse)
- Puerto 3000 abierto en firewall (cambiar a 8000)
- **Tarea: instalar WebODM, abrir puerto 8000, configurar port proxy**

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

### Port proxy (necesario cuando networkingMode=mirrored no propaga el puerto)
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

### En el .80 — hacer ahora

1. **Eliminar NodeODM y clonar WebODM:**
```powershell
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm 2>/dev/null; docker rm nodeodm 2>/dev/null; cd ~ && git clone https://github.com/OpenDroneMap/WebODM --config core.autocrlf=input -b master && cd WebODM && ./webodm.sh start --port 8000 --detach --default-nodes 0"
```

2. **Abrir firewall para puerto 8000:**
```powershell
New-NetFirewallRule -DisplayName "WebODM-8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
```

3. **Port proxy de Windows a WSL2:**
```powershell
$wslIp = (wsl -d Ubuntu hostname -I).Trim().Split(' ')[0]
netsh interface portproxy add v4tov4 listenport=8000 listenaddress=0.0.0.0 connectport=8000 connectaddress=$wslIp
```

4. **Verificar que responde (esperar 3 minutos):**
```powershell
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8000
```
Debe devolver `200` o `302`.

5. **Crear cuenta** en `http://localhost:8000` al abrir por primera vez.

6. **Agregar nodos** en WebODM → Nodos de procesamiento → Agregar:
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
