# Guía de Instalación WebODM
## IPRE IPI-26-704 — Red de Procesamiento Fotogramétrico

---

## Arquitectura del sistema

```
Tu PC / cualquier PC con Google Drive
        │
        │ python webodm_pipeline.py --config config_remoto.json
        ▼
PC Maestro (146.155.38.80:8000)  ←── WebODM (UI + orquestador)
        │
        │ distribuye tareas según disponibilidad
        ├──► PC-81 (146.155.38.81:3000)  ←── NodeODM (motor)
        └──► PC-82 (146.155.38.82:3000)  ←── NodeODM (motor)
```

- **WebODM** corre SOLO en el PC maestro (.80) — interfaz web y gestión de tareas
- **NodeODM** corre en los PCs trabajadores (.81, .82) — solo el motor de procesamiento
- Un nodo = un set de fotos procesándose en paralelo. Más nodos = más sets simultáneos
- Los trabajadores se instalan con `Nodos/instalar_nodeodm.ps1`

### Comportamiento automático garantizado

Los scripts configuran automáticamente tres mecanismos que mantienen el sistema estable:

| Mecanismo | Qué hace | Por qué es crítico |
|---|---|---|
| `systemd=true` en `/etc/wsl.conf` | Docker persiste vía systemd | Sin él Docker muere al cerrar la terminal |
| `vmIdleTimeout=-1` en `.wslconfig` | La VM de WSL2 nunca se apaga sola | Sin él WSL2 se apaga en ~5 min tirando todo |
| Tarea `WSL-KeepAlive` | Mantiene un proceso `wsl.exe` vivo 24/7 | Sin él vmIdleTimeout no es suficiente; la VM se apaga igual |

---

## Requisitos de hardware (PC maestro)

| Imágenes a procesar | RAM mínima |
|---|---|
| 40 | 4 GB |
| 250 | 16 GB |
| 500 | 32 GB |
| 1500 | 64 GB |

- CPU 64 bits con soporte SSE3/SSSE3 (prácticamente cualquier CPU desde 2008)
- 100 GB de espacio libre en disco
- Windows 11 con WSL2 disponible

---

## PARTE 1 — Instalar WebODM en el PC Maestro

### Archivos necesarios
Copiar a la misma carpeta en el PC maestro:
- `instalar_webodm.ps1`
- `instalar_docker_webodm.sh`

### Pasos

**1. Abrir PowerShell como Administrador**

```powershell
# Desde una PowerShell normal ya abierta en la carpeta correcta:
Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command Set-Location '$PWD'"
```

**2. Habilitar ejecución de scripts**
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

**3. Ejecutar el instalador**
```powershell
.\instalar_webodm.ps1
```

**4. Proceso automático (sin intervención)**

El script realiza todo esto solo:
1. Configura `.wslconfig` con `networkingMode=mirrored` y `vmIdleTimeout=-1`
2. Habilita WSL2 y lo configura en modo red espejo
3. Instala Ubuntu en WSL2
4. Abre el puerto 8000 en el firewall
5. Crea la tarea `WSL-KeepAlive` (mantiene WSL2 activo permanentemente)
6. Programa la Fase 2 para ejecutarse al reiniciar

Si necesita reinicio, el instalador lo indica y lo solicita.

**Al volver a iniciar sesión (Fase 2 automática):**
1. Habilita `systemd` en WSL2
2. Instala Docker Engine
3. Clona y arranca WebODM con `--default-nodes 0`
4. Crea la tarea `WebODM-Autostart`

> **`--default-nodes 0`** evita que WebODM registre un nodo interno `node-odx-1` al arrancar.
> Sin esta flag, si el nodo interno falla, `python manage.py addnode` consume 700%+ CPU
> bloqueando el arranque indefinidamente.

> **Si Ubuntu se queda pegado descargando:**
> ```powershell
> wsl --install -d Ubuntu --web-download --no-launch
> ```
> Luego volver a ejecutar `.\instalar_webodm.ps1`

**5. Verificar instalación**

Abrir en el navegador del PC maestro:
```
http://localhost:8000
```
Crear cuenta de administrador en el primer acceso.

> **Desde el PC maestro** siempre usar `http://localhost:8000` (no la IP de red).
> Esto evita el problema de *hairpin NAT*: un equipo no puede alcanzarse a sí mismo
> usando su propia IP de red local.

**6. Instalar Python y dependencias del pipeline**
```powershell
winget install Python.Python.3.11
```
Cerrar y reabrir PowerShell:
```powershell
pip install requests tqdm
```

---

## PARTE 2 — Agregar nodos trabajadores en WebODM

Una vez que los PCs trabajadores tienen NodeODM instalado (ver `Nodos/guia_instalación_nodos.md`):

En el PC maestro, abrir `http://localhost:8000`:

**Nodos de procesamiento → Agregar nuevo nodo**

| Campo | Valor |
|---|---|
| Nombre de host | IP del PC trabajador (ej: `146.155.38.81`) |
| Puerto | `3000` |
| Token | (dejar vacío) |
| Etiqueta | Nombre descriptivo (ej: `PC-81`) |

El nodo aparece en **verde** cuando la conexión es exitosa.
Si aparece en **rojo**, ver `Nodos/guia_instalación_nodos.md` → diagnóstico.

---

## PARTE 3 — Ejecutar el pipeline

### Desde el PC maestro (recomendado)
```powershell
python webodm_pipeline.py --config config.json --preset "Fast Orthophoto" ^
  --images "G:\Mi unidad\03.- PUC\06.- 2026\02.- Estudiantes\06.- DOP\02.- Fotos\NOMBRE_SET"
```
Usa `config.json` (localhost:8000). **No usar `config_remoto.json` desde el maestro** (hairpin NAT).

### Desde cualquier otro PC con Google Drive
```powershell
python webodm_pipeline.py --config config_remoto.json --preset "Fast Orthophoto" ^
  --images "G:\Mi unidad\03.- PUC\06.- 2026\02.- Estudiantes\06.- DOP\02.- Fotos\NOMBRE_SET"
```

### Presets disponibles

| Preset | Uso |
|---|---|
| `Fast Orthophoto` | Ortofoto rápida, baja resolución |
| `High Resolution` | Alta resolución, más lento |
| `3D Model` | Modelo 3D + ortofoto |
| `DSM + DTM` | Modelos de elevación digital |
| `Default` | Configuración estándar |

### Comandos útiles del pipeline

```powershell
# Listar presets disponibles
python webodm_pipeline.py --config config.json --list-presets

# Validar config sin enviar nada
python webodm_pipeline.py --config config.json --dry-run

# Subir fotos y salir (procesa en background)
python webodm_pipeline.py --config config.json --preset "Fast Orthophoto" --images "RUTA" --no-wait

# Descargar resultados de tarea ya procesada
python webodm_pipeline.py --config config.json --download TASK_ID --project-id PROJECT_ID
```

---

## PARTE 4 — Inicio automático tras reinicio

Las tareas programadas de Windows manejan todo:

| Tarea | Qué hace |
|---|---|
| `WSL-KeepAlive` | Mantiene WSL2 VM viva 24/7 (AtLogOn + AtStartup, restart 999 veces) |
| `WebODM-Autostart` | Inicia Docker y WebODM al iniciar sesión |

Para iniciar WebODM manualmente:
```powershell
wsl -d Ubuntu -u root -- bash -c "systemctl start docker; sleep 5; cd ~/WebODM && ./webodm.sh start --port 8000 --default-nodes 0 --detach"
```

---

## PARTE 5 — Diagnóstico rápido

```powershell
# Estado de contenedores Docker
wsl -d Ubuntu -u root -- docker ps

# Logs de WebODM
wsl -d Ubuntu -u root -- docker logs webapp --tail 30

# WebODM responde
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8000

# Docker activo con systemd
wsl -d Ubuntu -u root -- systemctl status docker --no-pager

# WSL-KeepAlive corriendo
Get-ScheduledTask -TaskName "WSL-KeepAlive" | Get-ScheduledTaskInfo

# Configuración de red WSL2
Get-Content "$env:USERPROFILE\.wslconfig"

# Configuración de systemd en Linux
wsl -d Ubuntu -u root -- cat /etc/wsl.conf
```

---

## PARTE 6 — Solución de problemas

### WebODM no arranca / crash loop

Síntoma: `docker logs webapp` muestra reinicio continuo.

```powershell
# Verificar systemd
wsl -d Ubuntu -u root -- systemctl status docker --no-pager

# Si systemd no está activo, verificar wsl.conf
wsl -d Ubuntu -u root -- cat /etc/wsl.conf
# Debe mostrar:
#   [boot]
#   systemd=true
# Si no, corregir:
wsl -d Ubuntu -u root -- bash -c "printf '[boot]\nsystemd=true\n' > /etc/wsl.conf"
wsl --shutdown
# Esperar 15 seg, volver a abrir WSL2
wsl -d Ubuntu -u root -- bash -c "systemctl start docker; sleep 5; cd ~/WebODM && ./webodm.sh start --port 8000 --default-nodes 0 --detach"
```

### WebODM se cae periódicamente (cada ~5 minutos)

Causa: WSL2 VM se apaga automáticamente.

```powershell
# Verificar vmIdleTimeout
Get-Content "$env:USERPROFILE\.wslconfig"
# Debe contener vmIdleTimeout=-1

# Si falta, corregir:
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value "[wsl2]`nnetworkingMode=mirrored`nvmIdleTimeout=-1`n" -Encoding UTF8

# Verificar WSL-KeepAlive
Get-ScheduledTask -TaskName "WSL-KeepAlive" | Get-ScheduledTaskInfo
# LastRunTime y NextRunTime deben ser recientes. Si no existe:
$a = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -u root -- bash -c `"while true; do sleep 3600; done`""
$t = @((New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME),(New-ScheduledTaskTrigger -AtStartup))
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RunOnlyIfNetworkAvailable:$false -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest
Register-ScheduledTask -TaskName "WSL-KeepAlive" -Action $a -Trigger $t -Settings $s -Principal $p -Force | Out-Null
Start-ScheduledTask -TaskName "WSL-KeepAlive"
```

### Puerto 8000 no accesible desde otros PCs

**Paso 1 — Verificar firewall:**
```powershell
Get-NetFirewallRule -DisplayName "WebODM-8000"
# Si no existe:
New-NetFirewallRule -DisplayName "WebODM-8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
```

**Paso 2 — Verificar `.wslconfig`:**
```powershell
Get-Content "$env:USERPROFILE\.wslconfig"
# Debe contener networkingMode=mirrored
```

**(Opcional) Paso 3 — Port proxy como fallback:**

Si `networkingMode=mirrored` no propaga el puerto a la red local:
```powershell
$wslIp = (wsl -d Ubuntu hostname -I).Trim().Split(' ')[0]
netsh interface portproxy delete v4tov4 listenport=8000 listenaddress=0.0.0.0 2>$null
netsh interface portproxy add v4tov4 listenport=8000 listenaddress=0.0.0.0 connectport=8000 connectaddress=$wslIp
```

Para hacerlo permanente (IP de WSL2 cambia con cada reinicio):
```powershell
$cmd = '& { $ip = (wsl -d Ubuntu hostname -I).Trim().Split('' '')[0]; netsh interface portproxy delete v4tov4 listenport=8000 listenaddress=0.0.0.0; netsh interface portproxy add v4tov4 listenport=8000 listenaddress=0.0.0.0 connectport=8000 connectaddress=$ip }'
$a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NonInteractive -Command `"$cmd`""
$t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
Register-ScheduledTask -TaskName "WebODM-PortProxy" -Action $a -Trigger $t -Settings (New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable:$false) -Principal $p -Force | Out-Null
Start-ScheduledTask -TaskName "WebODM-PortProxy"
```

> **Nota:** Con `networkingMode=mirrored` activo, el port proxy generalmente NO es necesario
> y puede causar conflictos. Intentar sin él primero.

### wsl.conf con claves duplicadas

Si WSL2 muestra `Duplicated config key 'boot.systemd'`:
```powershell
wsl -d Ubuntu -u root -- bash -c "printf '[boot]\nsystemd=true\n' > /etc/wsl.conf"
wsl --shutdown
```

### Ubuntu se queda pegado descargando

```powershell
wsl --install -d Ubuntu --web-download --no-launch
```

---

## Archivos del proyecto

| Archivo | Descripción |
|---|---|
| `WebODM/instalar_webodm.ps1` | Instalador WebODM, PC maestro (Fase 1, Windows) |
| `WebODM/instalar_docker_webodm.sh` | Instalador WebODM, PC maestro (Fase 2, WSL2) |
| `Nodos/instalar_nodeodm.ps1` | Instalador NodeODM, PC trabajador (Fase 1, Windows) |
| `Nodos/instalar_nodeodm.sh` | Instalador NodeODM, PC trabajador (Fase 2, WSL2) |
| `webodm_pipeline.py` | Script principal del pipeline fotogramétrico |
| `config.json` | Config local — usar desde el PC maestro (localhost:8000) |
| `config_remoto.json` | Config remota — usar desde otros PCs (146.155.38.80:8000) |
