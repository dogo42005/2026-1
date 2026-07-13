# Guía de Instalación WebODM + NodeODM
## IPRE IPI-26-704 — Red de Procesamiento Fotogramétrico

---

## Arquitectura del sistema

```
Tu PC / PC con Google Drive
        │
        │ python webodm_pipeline.py --config config_remoto.json
        ▼
PC Maestro (146.155.38.81:8000)  ←── WebODM (UI + orquestador)
        │
        │ distribuye tareas automáticamente
        ├──► node-odx-1 (nodo propio del .81)
        └──► PC-80 (146.155.38.80:3000)  ←── NodeODM (motor)
```

- **WebODM** corre en el PC maestro (.81) — interfaz web y gestión de tareas
- **NodeODM** corre en los PCs trabajadores (.80, etc.) — solo el motor de procesamiento
- Las fotos se suben al maestro y él distribuye el trabajo entre los nodos disponibles
- Un nodo = un set de fotos procesándose. Más nodos = más sets en paralelo

---

## Requisitos de hardware (por nodo)

| Imágenes | RAM mínima |
|---|---|
| 40 | 4 GB |
| 250 | 16 GB |
| 500 | 32 GB |
| 1500 | 64 GB |

- CPU 64 bits con soporte SSE3/SSSE3 (prácticamente cualquier CPU desde 2008)
- 100 GB de espacio libre en disco mínimo (más si se procesan miles de imágenes)
- GPU NVIDIA opcional — acelera procesamiento pero no es requerida

> **Error "Illegal instruction"** al procesar = el CPU es demasiado antiguo para las instrucciones requeridas por ODM en Docker. En ese caso se debe compilar ODM desde código fuente de forma nativa.

---

## PARTE 1 — Instalar WebODM en el PC Maestro

### Archivos necesarios
Copiar al PC maestro (misma carpeta):
- `instalar_webodm.ps1`
- `instalar_docker_webodm.sh`

### Pasos

**1. Abrir PowerShell como Administrador**

Opción A — desde el menú inicio:
- Buscar "PowerShell" → click derecho → "Ejecutar como administrador"

Opción B — desde una PowerShell normal ya abierta en la carpeta correcta:
```powershell
Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command Set-Location '$PWD'"
```
Esto abre una nueva ventana de PowerShell como administrador en la misma ruta actual.

**2. Habilitar ejecución de scripts**
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```
Responder `O` (Sí a todo)

**3. Ejecutar el instalador**
```powershell
.\instalar_webodm.ps1
```

**4. Proceso automático**
- Instala WSL2 + Ubuntu → **requiere reinicio**
- Al volver a iniciar sesión, continúa automáticamente
- Instala Docker Engine + WebODM dentro de WSL2
- Primera vez descarga imágenes Docker (~2 GB, 5-15 min)

> **Si Ubuntu se queda pegado descargando**, cancelar con Ctrl+C y ejecutar:
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

**6. Instalar Python y dependencias del pipeline**
```powershell
winget install Python.Python.3.11
```
Cerrar y reabrir PowerShell, luego:
```powershell
pip install requests tqdm
```

---

## PARTE 2 — Instalar NodeODM en PCs Trabajadores

### Archivos necesarios
Copiar al PC trabajador (misma carpeta):
- `instalar_nodeodm.ps1`
- `instalar_nodeodm.sh`

### Pasos

**1. Abrir PowerShell como Administrador y habilitar scripts**
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

**2. Ejecutar el instalador**
```powershell
.\instalar_nodeodm.ps1
```

**3. Proceso automático**
- Instala WSL2 + Ubuntu → puede requerir reinicio
- Instala Docker Engine + contenedor NodeODM
- NodeODM queda escuchando en el puerto 3000

**4. Verificar que NodeODM responde**
```powershell
wsl -d Ubuntu -u root -- curl http://localhost:3000
```
Debe devolver HTML con la interfaz de NodeODM. Si devuelve error, esperar 1 minuto e intentar de nuevo.

**5. (Opcional) Verificar conectividad sin procesar — Modo Test**

Para confirmar que NodeODM responde correctamente sin lanzar un procesamiento real:
```powershell
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm; docker rm nodeodm; docker run -d --name nodeodm --restart always -p 3000:3000 opendronemap/nodeodm --test"
```
En modo `--test` todas las llamadas a ODM son simuladas. Útil para verificar la integración con WebODM antes de procesar imágenes reales.

**6. (Opcional) Almacenar resultados en disco externo**

Si el PC tiene un disco secundario con más espacio, mapear la carpeta de datos:
```powershell
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm; docker rm nodeodm; docker run -d --name nodeodm --restart always -p 3000:3000 -v /mnt/d/nodeodm_data:/var/www/data opendronemap/nodeodm"
```
Reemplazar `/mnt/d/nodeodm_data` por la ruta del disco externo en WSL2 (ej: `D:\nodeodm_data` → `/mnt/d/nodeodm_data`).

**7. (Opcional) Aceleración GPU con tarjeta NVIDIA**

Primero verificar que Docker reconoce la GPU:
```powershell
wsl -d Ubuntu -u root -- bash -c "docker run --rm --gpus all nvidia/cuda:10.0-base nvidia-smi"
```
Si muestra la tabla con información de la GPU, proceder:
```powershell
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm; docker rm nodeodm; docker run -d --name nodeodm --restart always -p 3000:3000 --gpus all opendronemap/nodeodm:gpu"
```
> Solo funciona con GPUs NVIDIA. Requiere instalar NVIDIA Container Toolkit.

---

## PARTE 3 — Comandos de diagnóstico rápido

Antes de buscar en la solución de problemas, estos comandos ayudan a identificar qué está fallando:

```powershell
# Ver si el contenedor NodeODM está corriendo y hace cuánto
wsl -d Ubuntu -u root -- docker ps

# Ver logs de NodeODM (muestra errores internos)
wsl -d Ubuntu -u root -- docker logs nodeodm

# Ver si NodeODM responde desde dentro de WSL2
wsl -d Ubuntu -u root -- curl http://localhost:3000

# Ver si Docker está corriendo con systemd
wsl -d Ubuntu -u root -- systemctl status docker

# Ver configuración de red WSL2 (debe tener networkingMode=mirrored)
Get-Content "$env:USERPROFILE\.wslconfig"
```

---

## PARTE 4 — Solución de problemas comunes

### NodeODM se inicia y se cierra en loop

**Causa:** Docker daemon no persiste sin systemd.

**Solución:** Habilitar systemd en WSL2.

```powershell
# Limpiar wsl.conf y habilitar systemd
wsl -d Ubuntu -u root -- bash -c "printf '[boot]\nsystemd=true\n' > /etc/wsl.conf"

# Configurar red en modo espejo (archivo Windows, no Linux)
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value "[wsl2]`nnetworkingMode=mirrored`n" -Encoding UTF8

# Reiniciar WSL2
wsl --shutdown
```

Esperar 10 segundos, luego:
```powershell
wsl -d Ubuntu -u root -- bash -c "systemctl enable docker && systemctl start docker && sleep 5 && docker start nodeodm"
```

Verificar:
```powershell
wsl -d Ubuntu -u root -- docker ps
```
Debe mostrar el contenedor `nodeodm` con estado `Up`.

---

### Puerto 3000 no accesible desde otros PCs

**Causa:** El modo red espejo de WSL2 no está activo o el firewall bloquea el puerto.

**Paso 1 — Verificar y crear regla de firewall:**
```powershell
New-NetFirewallRule -DisplayName "NodeODM-3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow
```

**Paso 2 — Verificar `.wslconfig` en Windows:**
```powershell
Get-Content "$env:USERPROFILE\.wslconfig"
```
Debe mostrar:
```
[wsl2]
networkingMode=mirrored
```
Si no, crearlo:
```powershell
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value "[wsl2]`nnetworkingMode=mirrored`n" -Encoding UTF8
wsl --shutdown
```

**Paso 3 — Si el modo espejo no funciona, usar port proxy:**
```powershell
$wslIp = (wsl -d Ubuntu hostname -I).Trim().Split(' ')[0]
netsh interface portproxy add v4tov4 listenport=3000 listenaddress=0.0.0.0 connectport=3000 connectaddress=$wslIp
```

> El port proxy se pierde al reiniciar. Para hacerlo permanente, agregar este comando a una tarea programada de inicio.

**Paso 4 — Verificar desde otro PC en la red:**
```
http://146.155.38.80:3000
```

---

### wsl.conf con claves duplicadas

Si WSL2 muestra `Duplicated config key 'boot.systemd'`, limpiar el archivo:
```powershell
wsl -d Ubuntu -u root -- bash -c "printf '[boot]\nsystemd=true\n' > /etc/wsl.conf"
wsl --shutdown
```

---

### Error `-RunOnlyIfNetworkAvailable` en New-ScheduledTaskSettingsSet

Usar dos puntos antes del valor booleano:
```powershell
-RunOnlyIfNetworkAvailable:$false   # correcto
-RunOnlyIfNetworkAvailable $false   # incorrecto
```

---

### Ubuntu se queda pegado descargando

Agregar `--web-download` para descargar directamente desde internet:
```powershell
wsl --install -d Ubuntu --web-download --no-launch
```

---

## PARTE 5 — Agregar nodo trabajador en WebODM

En el PC maestro, abrir `http://localhost:8000`:

**Nodos de procesamiento → Agregar nuevo**

| Campo | Valor |
|---|---|
| Nombre de host | IP del PC trabajador (ej: `146.155.38.80`) |
| Puerto | `3000` |
| Token | (dejar vacío) |
| Etiqueta | Nombre descriptivo (ej: `PC-80`) |

El nodo aparece en **verde** cuando la conexión es exitosa.

---

## PARTE 6 — Ejecutar el pipeline

### Desde cualquier PC con acceso al Google Drive

```powershell
python webodm_pipeline.py --config config_remoto.json --preset "Fast Orthophoto" --images "G:\Mi unidad\03.- PUC\06.- 2026\02.- Estudiantes\06.- DOP\02.- Fotos\NOMBRE_SET"
```

### Desde el PC maestro (recomendado — sin transferencia de red)

```powershell
python webodm_pipeline.py --config config.json --preset "Fast Orthophoto" --images "G:\Mi unidad\03.- PUC\06.- 2026\02.- Estudiantes\06.- DOP\02.- Fotos\NOMBRE_SET"
```

### Presets disponibles

| Preset | Uso |
|---|---|
| `Fast Orthophoto` | Ortofoto rápida, baja resolución |
| `High Resolution` | Alta resolución, lento |
| `3D Model` | Modelo 3D + ortofoto |
| `DSM + DTM` | Modelos de elevación |
| `Default` | Configuración estándar |

### Comandos útiles del pipeline

```powershell
# Listar presets disponibles
python webodm_pipeline.py --config config_remoto.json --list-presets

# Validar config sin enviar nada
python webodm_pipeline.py --config config_remoto.json --dry-run

# Subir fotos y salir sin esperar (procesa en servidor)
python webodm_pipeline.py --config config_remoto.json --preset "Fast Orthophoto" --images "RUTA" --no-wait

# Descargar resultados de tarea ya procesada
python webodm_pipeline.py --config config_remoto.json --download TASK_ID --project-id PROJECT_ID
```

---

## PARTE 7 — Inicio automático tras reinicio

### WebODM (PC maestro)
La tarea programada `WebODM-Autostart` lo levanta automáticamente al iniciar sesión.

Para iniciarlo manualmente:
```powershell
wsl -d Ubuntu -u root -- bash -c "systemctl start docker; cd ~/WebODM && ./webodm.sh start --port 8000"
```

### NodeODM (PCs trabajadores)
La tarea programada `NodeODM-Autostart` lo levanta automáticamente al iniciar sesión.

Para iniciarlo manualmente:
```powershell
wsl -d Ubuntu -u root -- bash -c "systemctl start docker && sleep 5 && docker start nodeodm"
```

---

## Archivos del proyecto

| Archivo | Descripción |
|---|---|
| `instalar_webodm.ps1` | Instalador WebODM para PC maestro (Fase 1) |
| `instalar_docker_webodm.sh` | Instalador WebODM para WSL2 (Fase 2) |
| `instalar_nodeodm.ps1` | Instalador NodeODM para PCs trabajadores (Fase 1) |
| `instalar_nodeodm.sh` | Instalador NodeODM para WSL2 (Fase 2) |
| `webodm_pipeline.py` | Script principal del pipeline fotogramétrico |
| `config.json` | Config WebODM local (localhost:8000) |
| `config_remoto.json` | Config WebODM remoto (146.155.38.81:8000) |
| `config_maestro.json` | Config para orquestación multi-PC (futuro) |
| `lanzar_todos.ps1` | Script maestro para lanzar pipeline en varios PCs (futuro) |
| `habilitar_worker.ps1` | Habilita PC como worker via WinRM (futuro) |
