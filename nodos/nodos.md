Basado en la documentación oficial de WebODM y el repositorio de OpenDroneMap/NodeODM, a continuación te explico detalladamente y paso a paso cómo implementar NodeODM en distintos entornos y configuraciones.
# Guía Exhaustiva de Implementación de NodeODM
## 1. ¿Qué es NodeODM?
NodeODM es una implementación de referencia escrita en NodeJS que sirve como una API REST ligera. Su función principal es actuar como un "puente" o servidor de procesamiento que permite acceder a motores de procesamiento de imágenes aéreas (fotogrametría), principalmente *OpenDroneMap (ODM)* o *MicMac*. Clientes web o de escritorio como WebODM, CloudODM o PyODM se conectan a un servidor NodeODM para delegar el trabajo pesado de procesar los mapas, modelos 3D y ortofotos.
## 2. Requisitos Previos del Sistema
Aunque NodeODM en sí (la API) consume pocos recursos, el motor ODM subyacente que realiza los cálculos es altamente exigente.
 * *CPU:* Si utilizas Docker, tu procesador debe tener extensiones de 64 bits y soporte para conjuntos de instrucciones MMX, SSE, SSE2, SSE3 y SSSE3 o superiores. (Si al intentar procesar ves un error de "Illegal instruction", tu procesador es demasiado antiguo y deberás instalar el software nativamente compilando desde el código fuente).
 * *Memoria RAM:* Según la documentación, la memoria escala linealmente con la cantidad de imágenes a procesar:
   * *40 imágenes:* 4 GB RAM
   * *250 imágenes:* 16 GB RAM
   * *500 imágenes:* 32 GB RAM
   * *1500 imágenes:* 64 GB RAM
   * *2500 imágenes:* 128 GB RAM
 * *Almacenamiento:* Mínimo 100 GB de espacio libre (y mucho más si procesas miles de imágenes).
## 3. Instalación Recomendada: Docker
El método oficial y más estable de instalar y ejecutar NodeODM es mediante *Docker*, ya que empaqueta todas las dependencias necesarias.
### 3.1. Ejecución Básica (Windows, macOS, Linux)
 1. Instala Git y *Docker* (Docker Desktop en Windows/Mac o Docker Engine en Linux).
 2. Asigna suficientes recursos a Docker (ve a Settings -> Resources en Docker Desktop y asigna al menos 4GB de RAM y 2 CPUs, idealmente más).
 3. Abre una terminal (o Git Bash) y ejecuta el siguiente comando:
   bash
   docker run -p 3000:3000 opendronemap/nodeodm
   
   
 4. *Acceso:*
   * *Linux:* Abre un navegador web e ingresa a http://127.0.0.1:3000.
   * *Windows/macOS:* Ingresa a http://localhost:3000. Si usas una terminal antigua tipo Docker Quickstart Terminal, deberás buscar tu IP ejecutando docker-machine ip y acceder a http://<IP_DE_DOCKER>:3000.
 5. Verás la interfaz de NodeODM. Carga imágenes, presiona "Start Task" y la API comenzará a procesar.
### 3.2. Configurar Almacenamiento en un Disco Externo
Si deseas almacenar los proyectos terminados y datos temporales en un disco secundario con mayor capacidad, debes mapear un volumen local de tu máquina al volumen /var/www/data del contenedor:
bash
docker run -p 3000:3000 -v /ruta/hacia/tu/disco:/var/www/data opendronemap/nodeodm


Esto te permite también explorar los resultados del cálculo directamente desde el gestor de archivos de tu sistema operativo.
### 3.3. Aceleración por GPU (Sólo tarjetas NVIDIA)
Dado que OpenDroneMap soporta aceleración gráfica por hardware para acortar tiempos, existe una versión específica de NodeODM para aprovechar GPUs.
 1. Necesitas instalar los controladores de NVIDIA y el *NVIDIA Container Toolkit* (nvidia-docker).
 2. Verifica que Docker reconoce la GPU ejecutando:
   bash
   docker run --rm --gpus all nvidia/cuda:10.0-base nvidia-smi
   
   
   (Si el comando despliega una tabla con información de tu tarjeta, estás listo).
 3. Inicia NodeODM usando la etiqueta :gpu y permitiendo el acceso a la tarjeta:
   bash
   docker run -p 3000:3000 --gpus all opendronemap/nodeodm:gpu
   
   
## 4. Instalaciones Alternativas
### 4.1. Instalación Rootless (Sin permisos de superusuario) con Apptainer
En entornos de supercomputación o Clústeres (HPC) donde no tienes permisos de root para correr Docker, puedes usar *Apptainer*.
 1. Pide al administrador del clúster o alguien con permisos root que construya el contenedor base desde la carpeta de NodeODM:
   bash
   apptainer build --sandbox node/ apptainer.def
   
   
 2. Ya con el contenedor construido, ejecuta NodeODM nativamente en el clúster sin permisos root:
   bash
   apptainer run --writable node/
   
   
### 4.2. Instalación en Windows mediante Bundle Autocontenido
NodeODM puede ejecutarse como un binario en Windows sin descargar dependencias de Node, pero requiere que OpenDroneMap esté preinstalado en el sistema por separado.
 1. Ve a la página de Releases del repositorio de GitHub.
 2. Descarga el paquete nodeodm-windows-x64.zip.
 3. Extrae el contenido en una carpeta y ejecútalo mediante la línea de comandos, apuntando hacia donde tienes la instalación de ODM:
   cmd
   nodeodm.exe --odm_path c:\ruta\a\OpenDroneMap
   
   
### 4.3. Instalación Nativa en Ubuntu Linux (Código Fuente)
Si no deseas usar Docker (por hardware incompatible o configuraciones a medida):
 1. Instala el motor *Entwine* siguiendo las instrucciones de entwine.io.
 2. Instala NodeJS, dependencias de Python y utilidades para descomprimir:
   bash
   sudo curl --silent --location https://deb.nodesource.com/setup_6.x | sudo bash -
   sudo apt-get install -y nodejs python-gdal p7zip-full unzip
   
   
 3. Clona el repositorio y descarga paquetes de Node:
   bash
   git clone https://github.com/OpenDroneMap/NodeODM
   cd NodeODM
   npm install
   
   
 4. Ejecuta la aplicación:
   bash
   node index.js
   
   
   Nota: Si la consola arroja un error porque no encuentra OpenDroneMap, deberás forzar la ruta:
   node index.js --odm_path /home/tu_usuario/OpenDroneMap
## 5. Gestión del Proceso Nativo con PM2
Si optaste por la instalación Nativa en Linux (4.3), es altamente recomendado correr NodeODM como un servicio en segundo plano para que se reinicie automáticamente tras una falla o al encender el servidor. Para ello se utiliza *PM2*.
 1. Instala PM2 globalmente:
   bash
   sudo npm install pm2 -g
   
   
 2. En la carpeta de NodeODM, inicia el proceso con el archivo JSON preconfigurado:
   bash
   pm2 start processes.json
   
   
 3. Guarda la configuración y configúralo para que arranque junto con el sistema operativo:
   bash
   pm2 save
   pm2 startup
   
   
   (Sigue las instrucciones textuales que el último comando imprima en la consola; generalmente pide copiar y pegar un comando adicional).
 4. Puedes verificar si tu nodo está en línea usando: pm2 status
## 6. Modo de Prueba (Test Mode)
Si solo estás configurando el sistema para integrarlo a WebODM, o si eres desarrollador y no deseas ejecutar OpenDroneMap para probar que la API funciona, puedes iniciarla en modo prueba. En este modo, todas las peticiones a OpenDroneMap serán simuladas, retornando datos falsos preconfigurados.
bash
node index.js --test


## 7. Integración Práctica con WebODM
Para entender su lugar en el ecosistema: *WebODM* es el panel de control gráfico (la aplicación web general) y *NodeODM* es el obrero que calcula.
 1. Al instalar WebODM, por defecto este levanta un contenedor llamado node-odx-1 para empezar a trabajar de inmediato.
 2. Si los recursos de la máquina de WebODM se acaban, puedes usar las instrucciones de esta guía para levantar múltiples instancias de *NodeODM* en distintas computadoras o servidores en la nube.
 3. Dentro de WebODM, vas al menú de *Processing Nodes*, haces clic en agregar, e ingresas la dirección IP y el puerto (ej. 3000) de los servidores NodeODM que acabas de configurar. Esto te permitirá delegar cálculos enormes hacia clústeres externos, construyendo una red de procesamiento.

---

## 8. Implementación en este proyecto — IPRE IPI-26-704

### Arquitectura real desplegada

```
PC Maestro (146.155.38.81)          PC Trabajador (146.155.38.80)
─────────────────────────           ──────────────────────────────
Windows 11                          Windows 11
└── WSL2 (Ubuntu + systemd)         └── WSL2 (Ubuntu + systemd)
    └── Docker Engine                   └── Docker Engine
        ├── WebODM (puerto 8000)            └── NodeODM (puerto 3000)
        └── node-odx-1 (nodo propio)
```

NodeODM **no** se instaló con Docker Desktop sino con **Docker Engine dentro de WSL2**, evitando la EULA interactiva de Docker Desktop. Ver scripts `instalar_nodeodm.ps1` + `instalar_nodeodm.sh`.

### Diferencias clave con la instalación estándar (Docker Desktop)

| Aspecto | Docker Desktop | Docker Engine en WSL2 (este proyecto) |
|---|---|---|
| EULA interactiva | Sí | No |
| Persistencia del daemon | Automática | Requiere systemd en WSL2 |
| Acceso de red desde Windows | Automático | Requiere `networkingMode=mirrored` en `.wslconfig` |
| Acceso desde otros PCs | Automático | Requiere regla de firewall + port proxy si mirrored falla |

### Problemas encontrados en la práctica

**1. NodeODM arranca y se cierra en loop**

Causa: Docker daemon muere cuando termina la sesión WSL2 (sin systemd no hay persistencia).

Solución: habilitar systemd en `/etc/wsl.conf` y `systemctl enable docker`.

```bash
printf '[boot]\nsystemd=true\n' > /etc/wsl.conf
```

**2. Puerto 3000 no accesible desde otros PCs en la red**

Causa: `networkingMode=mirrored` estaba en `/etc/wsl.conf` (Linux) en vez de `~/.wslconfig` (Windows).

Solución: el archivo correcto es `C:\Users\Usuario\.wslconfig`:
```
[wsl2]
networkingMode=mirrored
```

Alternativa si mirrored no funciona — port proxy manual:
```powershell
$wslIp = (wsl -d Ubuntu hostname -I).Trim().Split(' ')[0]
netsh interface portproxy add v4tov4 listenport=3000 listenaddress=0.0.0.0 connectport=3000 connectaddress=$wslIp
```

**3. wsl.conf con claves duplicadas**

Causa: el script ejecutado varias veces agregó `[boot] systemd=true` más de una vez.

Solución: sobreescribir el archivo completo:
```bash
printf '[boot]\nsystemd=true\n' > /etc/wsl.conf
```

### Modo Test — verificar conectividad antes de procesar

Útil para confirmar que WebODM puede hablar con NodeODM sin lanzar un procesamiento real:

```bash
docker stop nodeodm
docker rm nodeodm
docker run -d --name nodeodm --restart always -p 3000:3000 opendronemap/nodeodm --test
```

En modo `--test` todas las llamadas a ODM son simuladas. Si el nodo aparece en verde en WebODM con este modo, la red está correcta.

### Comandos de diagnóstico rápido

```powershell
# Estado del contenedor
wsl -d Ubuntu -u root -- docker ps

# Logs internos (muestra si NodeODM falla al iniciar)
wsl -d Ubuntu -u root -- docker logs nodeodm

# Verificar respuesta desde dentro de WSL2
wsl -d Ubuntu -u root -- curl http://localhost:3000

# Estado de Docker con systemd
wsl -d Ubuntu -u root -- systemctl status docker
```

### Inicio automático configurado

La tarea programada de Windows `NodeODM-Autostart` ejecuta al iniciar sesión:
```
wsl -d Ubuntu -u root -- bash -c "systemctl start docker && sleep 5 && docker start nodeodm"
```

Para iniciar manualmente:
```powershell
wsl -d Ubuntu -u root -- bash -c "systemctl start docker && sleep 5 && docker start nodeodm"
```