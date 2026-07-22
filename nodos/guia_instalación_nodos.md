# Guía de Instalación NodeODM
## IPRE IPI-26-704 — PCs Trabajadores del Cluster Fotogramétrico

Esta guía aplica a cualquier PC que actúe como trabajador (motor de procesamiento).
El PC maestro con WebODM se instala con `WebODM/guia_instalacion.md`.

---

## Rol del PC trabajador

- Corre **NodeODM** en el puerto 3000 (motor de procesamiento, sin interfaz web)
- WebODM en el PC maestro (.80) le envía trabajos automáticamente
- Un nodo puede procesar un set de fotos a la vez
- Se puede agregar cualquier número de nodos al maestro

### Comportamiento automático garantizado

Los scripts configuran tres mecanismos que mantienen NodeODM estable:

| Mecanismo | Qué hace | Por qué es crítico |
|---|---|---|
| `systemd=true` en `/etc/wsl.conf` | Docker persiste vía systemd | Sin él Docker muere al cerrar la terminal |
| `vmIdleTimeout=-1` en `.wslconfig` | La VM de WSL2 nunca se apaga sola | Sin él WSL2 se apaga en ~5 min tirando todo |
| Tarea `WSL-KeepAlive` | Mantiene un proceso `wsl.exe` vivo 24/7 | Sin él vmIdleTimeout no es suficiente |

---

## Requisitos de hardware

| Imágenes a procesar | RAM mínima |
|---|---|
| 40 | 4 GB |
| 250 | 16 GB |
| 500 | 32 GB |
| 1500 | 64 GB |

- Windows 11 con WSL2 disponible
- 50 GB de espacio libre en disco (más si se procesan muchas imágenes)

---

## PARTE 1 — Instalar NodeODM

### Archivos necesarios
Copiar a la misma carpeta en el PC trabajador:
- `instalar_nodeodm.ps1`
- `instalar_nodeodm.sh`

### Pasos

**1. Abrir PowerShell como Administrador**
```powershell
Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command Set-Location '$PWD'"
```

**2. Habilitar ejecución de scripts**
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

**3. Ejecutar el instalador**
```powershell
.\instalar_nodeodm.ps1
```

**4. Proceso automático (sin intervención)**

El script realiza todo esto solo:
1. Configura `.wslconfig` con `networkingMode=mirrored` y `vmIdleTimeout=-1`
2. Habilita WSL2 en modo red espejo
3. Instala Ubuntu en WSL2
4. Abre el puerto 3000 en el firewall
5. Crea la tarea `WSL-KeepAlive` (mantiene WSL2 activo permanentemente)
6. Programa la Fase 2 para ejecutarse al reiniciar

**Al volver a iniciar sesión (Fase 2 automática):**
1. Habilita `systemd` en WSL2
2. Instala Docker Engine
3. Descarga y arranca el contenedor NodeODM
4. Crea la tarea `NodeODM-Autostart`

> **Si Ubuntu se queda pegado descargando:**
> ```powershell
> wsl --install -d Ubuntu --web-download --no-launch
> ```
> Luego volver a ejecutar `.\instalar_nodeodm.ps1`

**5. Verificar NodeODM**
```powershell
Start-Sleep 20
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
```
Debe devolver `200`. Si devuelve `000`, esperar 1 minuto e intentar de nuevo.

---

## PARTE 2 — Agregar el nodo al maestro WebODM

Una vez NodeODM responde `200`:

En el **PC maestro** abrir `http://146.155.38.80:8000` (o localhost:8000 si estás en el maestro):

**Nodos de procesamiento → Agregar nuevo nodo**

| Campo | Valor |
|---|---|
| Nombre de host | IP de este PC trabajador (ej: `146.155.38.81`) |
| Puerto | `3000` |
| Token | (dejar vacío) |
| Etiqueta | Nombre descriptivo (ej: `PC-81`) |

El nodo aparece en **verde** cuando la conexión es exitosa.

---

## PARTE 3 — Inicio automático tras reinicio

Las tareas programadas de Windows manejan todo:

| Tarea | Qué hace |
|---|---|
| `WSL-KeepAlive` | Mantiene WSL2 VM viva 24/7 |
| `NodeODM-Autostart` | Inicia Docker y NodeODM al iniciar sesión |

Para iniciar NodeODM manualmente:
```powershell
wsl -d Ubuntu -u root -- bash -c "systemctl start docker 2>/dev/null || service docker start 2>/dev/null; sleep 5; docker start nodeodm"
```

---

## PARTE 4 — Diagnóstico rápido

```powershell
# Estado del contenedor
wsl -d Ubuntu -u root -- docker ps

# Logs de NodeODM (ver últimas 20 líneas)
wsl -d Ubuntu -u root -- docker logs nodeodm --tail 20

# NodeODM responde (debe devolver 200)
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:3000

# Docker activo con systemd
wsl -d Ubuntu -u root -- systemctl status docker --no-pager

# WSL-KeepAlive corriendo
Get-ScheduledTask -TaskName "WSL-KeepAlive" | Get-ScheduledTaskInfo

# Configuración de red WSL2
Get-Content "$env:USERPROFILE\.wslconfig"

# Verificar systemd en Linux
wsl -d Ubuntu -u root -- cat /etc/wsl.conf
```

---

## PARTE 5 — Solución de problemas

### NodeODM en crash loop (arranca y se cierra)

Síntoma: `docker logs nodeodm --tail 20` muestra `Server has started on port 3000` seguido de `Closing server` y `Exiting...`.

Causa más probable: WSL2 VM se apagó y está reiniciando, llevando los contenedores con ella.

```powershell
# 1. Verificar systemd
wsl -d Ubuntu -u root -- systemctl status docker --no-pager

# 2. Si docker está inactive, verificar wsl.conf
wsl -d Ubuntu -u root -- cat /etc/wsl.conf
# Debe mostrar:
#   [boot]
#   systemd=true
# Si no, corregir y reiniciar WSL2:
wsl -d Ubuntu -u root -- bash -c "printf '[boot]\nsystemd=true\n' > /etc/wsl.conf"
wsl --shutdown
Start-Sleep 15
wsl -d Ubuntu -u root -- bash -c "systemctl start docker && sleep 5 && docker start nodeodm"

# 3. Verificar vmIdleTimeout
Get-Content "$env:USERPROFILE\.wslconfig"
# Debe contener vmIdleTimeout=-1
# Si no:
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value "[wsl2]`nnetworkingMode=mirrored`nvmIdleTimeout=-1`n" -Encoding UTF8
wsl --shutdown

# 4. Verificar WSL-KeepAlive
Get-ScheduledTask -TaskName "WSL-KeepAlive" | Get-ScheduledTaskInfo
# Si no existe o está detenida, recrear:
$a = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -u root -- bash -c `"while true; do sleep 3600; done`""
$t = @((New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME),(New-ScheduledTaskTrigger -AtStartup))
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RunOnlyIfNetworkAvailable:$false -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest
Register-ScheduledTask -TaskName "WSL-KeepAlive" -Action $a -Trigger $t -Settings $s -Principal $p -Force | Out-Null
Start-ScheduledTask -TaskName "WSL-KeepAlive"
```

### Nodo aparece en rojo en WebODM

```powershell
# Verificar que responde en la red
# (ejecutar desde el PC maestro u otro PC):
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://IP_WORKER:3000

# Si responde desde dentro pero no desde afuera:
# 1. Verificar firewall
Get-NetFirewallRule -DisplayName "NodeODM-3000"
# Si no existe:
New-NetFirewallRule -DisplayName "NodeODM-3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow

# 2. Verificar networkingMode
Get-Content "$env:USERPROFILE\.wslconfig"
# Debe contener networkingMode=mirrored
# Si no, ver sección "(Opcional) Port proxy" más abajo
```

### Reconstruir contenedor limpio

```powershell
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm; docker rm nodeodm; docker pull opendronemap/nodeodm; docker run -d --name nodeodm --restart always -p 3000:3000 opendronemap/nodeodm"
Start-Sleep 20
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
```

---

## (Opcional) Port proxy — solo si mirrored no funciona

Con `networkingMode=mirrored` el puerto 3000 de WSL2 ya es visible en la red local
a través de la IP de Windows. El port proxy **no es necesario en la mayoría de los casos**
y puede causar conflictos. Intentar sin él primero.

Si tras verificar firewall y `.wslconfig` el puerto sigue inaccesible desde otros PCs:

```powershell
# Aplicar una vez:
$wslIp = (wsl -d Ubuntu hostname -I).Trim().Split(' ')[0]
netsh interface portproxy delete v4tov4 listenport=3000 listenaddress=0.0.0.0 2>$null
netsh interface portproxy add v4tov4 listenport=3000 listenaddress=0.0.0.0 connectport=3000 connectaddress=$wslIp
```

Para hacerlo permanente (la IP WSL2 cambia con cada reinicio):
```powershell
$cmd = '& { $ip = (wsl -d Ubuntu hostname -I).Trim().Split('' '')[0]; netsh interface portproxy delete v4tov4 listenport=3000 listenaddress=0.0.0.0; netsh interface portproxy add v4tov4 listenport=3000 listenaddress=0.0.0.0 connectport=3000 connectaddress=$ip }'
$a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NonInteractive -Command `"$cmd`""
$t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
Register-ScheduledTask -TaskName "NodeODM-PortProxy" -Action $a -Trigger $t -Settings (New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable:$false) -Principal $p -Force | Out-Null
Start-ScheduledTask -TaskName "NodeODM-PortProxy"
```

---

## (Opcional) Almacenar resultados en disco externo

```powershell
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm; docker rm nodeodm; docker run -d --name nodeodm --restart always -p 3000:3000 -v /mnt/d/nodeodm_data:/var/www/data opendronemap/nodeodm"
```
Reemplazar `/mnt/d/nodeodm_data` por la ruta WSL2 del disco externo (`D:\` → `/mnt/d/`).

---

## (Opcional) Aceleración GPU con NVIDIA

```powershell
# Verificar que Docker ve la GPU:
wsl -d Ubuntu -u root -- bash -c "docker run --rm --gpus all nvidia/cuda:10.0-base nvidia-smi"
# Si muestra la tabla de la GPU, proceder:
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm; docker rm nodeodm; docker run -d --name nodeodm --restart always -p 3000:3000 --gpus all opendronemap/nodeodm:gpu"
```
Solo funciona con GPUs NVIDIA. Requiere NVIDIA Container Toolkit instalado.
