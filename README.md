# Pipeline WebODM — IPRE IPI-26-704

Script Python para lanzar fotogrametría en WebODM vía API REST,
con parámetros configurables desde un archivo `.json`.

---

## Caso A — WebODM y las fotos ya están en el PC remoto

En este caso el equipo remoto tiene WebODM corriendo y las fotos ya están accesibles en algún directorio de ese mismo sistema.

### 1. Requisitos previos

- Python 3.11+ instalado en el PC remoto
- WebODM ejecutándose (por defecto en `http://localhost:8000`)
- Dependencias Python:

```bash
pip install requests tqdm
```

### 2. Configurar `config.json`

Edita los campos mínimos según tu entorno:

```json
{
  "webodm": {
    "host": "http://localhost:8000",
    "username": "admin",
    "password": "tu_contraseña"
  },
  "task": {
    "images_dir": "/ruta/absoluta/a/las/fotos"
  }
}
```

### 3. Ejecutar el pipeline

```bash
# Con la ruta de fotos definida en config.json
python webodm_pipeline.py --config config.json

# Sobreescribir la ruta de fotos desde la línea de comandos
python webodm_pipeline.py --config config.json --images /ruta/absoluta/a/las/fotos

# Validar configuración sin enviar a WebODM
python webodm_pipeline.py --config config.json --dry-run
```

Los entregables quedan en WebODM del PC remoto, accesibles desde `http://localhost:8000` en ese mismo equipo. Si no querés que el script espere ni descargue nada, usá `--no-wait`.

---

## Caso B — Las fotos originales están en tu PC local

WebODM corre en un PC remoto, pero las imágenes están en tu equipo local y hay que transferirlas primero.

### 1. Requisitos previos

- Python 3.11+ en tu PC local
- Acceso SSH al PC remoto (con clave o contraseña)
- `scp` disponible (incluido en Windows 10+, macOS y Linux)
- WebODM ejecutándose en el PC remoto
- Dependencias Python en tu PC local:

```bash
pip install requests tqdm
```

### 2. Transferir las fotos al PC remoto

```bash
# Copiar un directorio completo de fotos al PC remoto
scp -r ./FOTOS/03.-\ Edificio\ Raúl\ Devés usuario@ip-remota:/home/usuario/fotos/raul_deves

# Si el puerto SSH no es el 22
scp -P 2222 -r ./FOTOS/06.-\ Edificio\ C usuario@ip-remota:/home/usuario/fotos/edificio_c
```

> Alternativa: montar la carpeta remota como unidad de red (SFTP con WinSCP / SSHFS en Linux/macOS) y apuntar el script directamente a esa ruta montada.

### 3. Configurar `config.json`

El host ahora apunta al PC remoto. Las fotos ya están en el remoto tras la transferencia:

```json
{
  "webodm": {
    "host": "http://ip-remota:8000",
    "username": "admin",
    "password": "tu_contraseña"
  },
  "task": {
    "images_dir": "/home/usuario/fotos/raul_deves"
  }
}
```

> Si WebODM no está expuesto públicamente, primero abre un túnel SSH:
> ```bash
> ssh -L 8000:localhost:8000 usuario@ip-remota
> ```
> Luego usa `host: "http://localhost:8000"` en el config y ejecuta el script normalmente desde tu PC local.

### 4. Ejecutar el pipeline desde tu PC local

```bash
# Sube las fotos, lanza la tarea y termina — los outputs quedan en el remoto
python webodm_pipeline.py --config config.json --no-wait

# Validar sin enviar
python webodm_pipeline.py --config config.json --dry-run
```

Con `--no-wait` el script sube las fotos, inicia el procesamiento y cierra la conexión. El PC remoto sigue procesando solo. Los entregables quedan almacenados en WebODM del remoto; accedé a ellos desde `http://ip-remota:8000` en el navegador, o con el túnel SSH si el puerto no está expuesto.

Cuando el procesamiento termine y quieras descargar los resultados de un remoto específico:

```bash
python webodm_pipeline.py --config config.json --download <TASK_ID> --project-id <PROJECT_ID>
```

El script imprime el `TASK_ID` y `PROJECT_ID` al momento de lanzar la tarea.

> Para correr varios remotos en paralelo, repetí los pasos 2–4 para cada equipo usando un `config.json` distinto con la `ip-remota` correspondiente. Cada PC procesa su propio set de fotos de forma independiente.

---

## Referencia

### Estructura del config.json

| Sección    | Descripción |
|------------|-------------|
| `webodm`   | Host, usuario y contraseña de WebODM |
| `project`  | Nombre y descripción del proyecto |
| `task`     | Nombre de la tarea, directorio de fotos y directorio de salida |
| `options`  | Parámetros de procesamiento OpenDroneMap |
| `exports`  | Qué entregables descargar (ortofoto, nube, modelo 3D, PDF) |
| `polling`  | Intervalo y timeout de monitoreo |

### Opciones clave de procesamiento

| Opción | Descripción | Valor recomendado |
|--------|-------------|-------------------|
| `orthophoto-resolution` | GSD en cm/pixel | 5 (rápido) / 2 (detalle) |
| `pc-quality` | Calidad nube de puntos | `medium` / `high` / `ultra` |
| `feature-quality` | Calidad detección de puntos | `high` |
| `dsm` | Generar modelo de superficie | `true` |
| `dtm` | Generar modelo de terreno | `true` |
| `mesh-octree-depth` | Detalle del modelo 3D | 11 (bueno) / 13 (lento) |

### Entregables generados

- `odm_orthophoto.tif` → importar en **Civil 3D** (Geoubicación)
- `nube_de_puntos.las` → importar en **ReCap Pro** o Civil 3D
- `modelo_3d.zip` → contiene `.OBJ` + texturas
- `reporte.pdf` → métricas de calidad del procesamiento

### Próximos pasos (OE2)

Este script se extenderá para:
1. Extraer imágenes individuales donde aparecen GCPs
2. Recortar patches alrededor de los GCPs para el dataset de entrenamiento
3. Generar anotaciones en formato YOLO para entrenamiento del modelo CNN
