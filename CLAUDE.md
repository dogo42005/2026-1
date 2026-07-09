# IPRE IPI-26-704 — Detector de GCPs en Imágenes UAV

## Quién soy
Diego Jesús Olivares Pérez — Licenciatura en Ingeniería en Ciencia de Datos, PUC, 5to semestre.  
Correo: diegoolivares42005@estudiante.uc.cl  
Profesor guía: José Isaac Lemus Romani (Escuela de Construcción Civil UC).  
IPRE formal: 09/07/2026 – 14/08/2026, 120 horas. Trabajo preparatorio desde junio 2026.

## Objetivo del proyecto
Desarrollar un algoritmo de Deep Learning (YOLOv8) que detecte automáticamente GCPs (tableros de ajedrez ~50×50 cm) en imágenes aéreas UAV, para reducir el trabajo manual en el flujo fotogramétrico y optimizar la georreferenciación.

## Objetivos específicos
- **OE1:** Dataset etiquetado de imágenes UAV con GCPs anotados en formato YOLO
- **OE2:** Entrenar YOLOv8 y evaluar con precisión / recall / F1-score
- **OE3:** Explorar conceptualmente la integración del modelo en el flujo WebODM/ODM

## Qué es un GCP
Marca física en el terreno (tablero de ajedrez blanco/negro, ~50×50 cm) con coordenadas GPS de precisión centimétrica (GNSS diferencial). Reduce el error de georreferenciación de 2–5 m a 2–5 cm.

En WebODM: archivo `gcp_list.txt` con formato `EPSG:32719 Este Norte Elevacion GCP foto.JPG px py`.  
La CNN debe predecir la bounding box del tablero en cada imagen JPG.

## Software del flujo fotogramétrico

| Software | Rol |
|---|---|
| WebODM (`localhost:8000`, Docker) | UI + orquestador: recibe JPGs, genera entregables |
| OpenDroneMap (ODM) | Engine: features → matching → SfM → MVS → DEM → orthophoto |
| Autodesk Civil 3D | Importa ortofoto TIF vía Geoubicación |
| Autodesk ReCap Pro | Visualiza nubes de puntos `.las` / `.rcp` |

## Estado actual de archivos

| Archivo | Estado | Descripción |
|---|---|---|
| `webodm_pipeline.py` | ✓ Hecho | Script principal: autentica JWT, crea proyecto, sube imgs, polling, descarga entregables |
| `config.json` | ✓ Hecho | Config base WebODM/ODM con parámetros de procesamiento |
| `README.md` | ✓ Hecho | Documentación de uso del pipeline |
| `dataset/exploracion_fotos.py` | Pendiente | EXIF + detección de GCPs por set de fotos |
| `dataset/multi_parametrization.py` | Pendiente | Genera configs variando parámetros y lanza tareas en lote |
| `labeling/gcp_labeler.py` | Pendiente | Herramienta interactiva OpenCV para etiquetar GCPs en formato YOLO |
| `dataset/prepare_splits.py` | Pendiente | Crea estructura YOLO y splits train/val/test |

## Datos disponibles

### Fotos en `FOTOS/` (local)
- `03.- Edificio Raúl Devés` — ya procesado, ortofoto generada
- `06.- Edificio C - DroneDeploy` — pendiente de procesar
- Otros sets pendientes de explorar

### SharePoint prof. Lemus
- **02.- Fotos:** imágenes RAW de vuelos del campus UC (fuente principal para OE1)
- **03.- Ortofotografías:** 5 ortofotos ya procesadas (.tif, 215–540 MB c/u)
- **02.- Grillas de inspección:** 4 sets de inspección de fachadas/techumbre (pueden o no tener GCPs)
- **04.- Nubes de Puntos:** Piscina GR (.rcp)
- **05.- Modelos 3D:** archivos .3sm (ReCap Photo)

### Primera tarea al explorar las fotos (OE1)
1. Verificar que tienen EXIF GPS
2. Revisar visualmente si hay GCPs (tableros) visibles en el suelo
3. Separar sets CON GCPs (para dataset) de sets SIN GCPs (solo fotogrametría)
4. Etiquetar los GCPs en formato YOLO

## Parámetros clave WebODM/ODM

| Parámetro | Descripción | Valores usados |
|---|---|---|
| `orthophoto-resolution` | GSD en cm/px | 2, 5, 10 |
| `pc-quality` | Calidad nube de puntos | medium, high, ultra |
| `feature-quality` | Detección de features | medium, high |
| `dsm` / `dtm` | Modelos de elevación | true |
| `use-3dmesh` | Modelo 3D OBJ | true |
| `mesh-octree-depth` | Detalle malla | 11, 13 |

## Formato de etiqueta YOLO
Un archivo `.txt` por imagen, una línea por GCP detectado:
```
<class_id> <x_center> <y_center> <width> <height>
```
Valores normalizados a [0,1]. Clase única: `0 = gcp`.

## Estructura de carpetas
```
2026-1/
├── CLAUDE.md                       ← este archivo
├── PROYECTO_CONTEXTO.md            ← (reemplazado por este CLAUDE.md)
├── README.md
├── laude.md                        ← resumen de contexto del proyecto
├── webodm_pipeline.py
├── config.json
├── context/                        ← PDFs del curso y formulario IPRE
├── FOTOS/                          ← imágenes UAV organizadas por set
│   ├── 03.- Edificio Raúl Devés/
│   └── 06.- Edificio C - DroneDeploy/
├── dataset/
│   ├── raw/                        ← copia organizada de FOTOS/ (por set)
│   ├── labeled/                    ← imágenes confirmadas con GCPs + labels YOLO
│   ├── exploracion_fotos.py
│   ├── multi_parametrization.py
│   ├── prepare_splits.py
│   └── yolo/
│       ├── data.yaml
│       ├── train/images/ + labels/
│       ├── val/images/ + labels/
│       └── test/images/ + labels/
├── labeling/
│   └── gcp_labeler.py
├── models/                         ← modelos entrenados (.pt)
├── notebooks/
│   ├── 01_exploracion_datos.ipynb
│   ├── 02_entrenamiento.ipynb
│   └── 03_evaluacion.ipynb
└── outputs/                        ← resultados WebODM por set
    └── <nombre_set>_<calidad>/
```

## Stack técnico
```
Python 3.11+
ultralytics      # YOLOv8
torch            # PyTorch backend
opencv-python    # procesamiento imágenes + herramienta etiquetado
Pillow / piexif  # lectura EXIF + GPS
requests         # WebODM REST API
tqdm             # barras de progreso
pandas           # análisis de reportes
PyYAML           # data.yaml para YOLOv8
```

## Plan de trabajo

| Semana | Fecha | Actividad |
|---|---|---|
| 1 | 23–30 jun | WebODM instalado, script pipeline, diagrama de flujo |
| 2 | 30 jun–7 jul | Ortofotos de todos los sets, comparación de parametrizaciones |
| 3 | 7–14 jul | Construcción dataset, etiquetado manual de GCPs |
| 4 | 14–21 jul | Implementación y entrenamiento YOLOv8 |
| 5 | 21–28 jul | Evaluación, integración conceptual WebODM, informe final |

## Convenciones de código
- Variables, comentarios y prints en español
- Nombres de archivos en minúsculas con guión bajo
- Cada script tiene `argparse` con `--help` útil
- Outputs del pipeline van a `outputs/<nombre_set>_<calidad>/`
- Labels YOLO en `dataset/labeled/<nombre_set>/labels/`

## Comandos frecuentes
```bash
# Pipeline base (un set)
python webodm_pipeline.py --config config.json

# Sobreescribir directorio de imágenes
python webodm_pipeline.py --config config.json --images ./FOTOS/06.-\ Edificio\ C\ -\ DroneDeploy

# Validar config sin enviar a WebODM
python webodm_pipeline.py --config config.json --dry-run

# Explorar sets de fotos (pendiente)
python dataset/exploracion_fotos.py --dir FOTOS/ --output reporte_exif.csv

# Lanzar comparación de parametrizaciones (pendiente)
python dataset/multi_parametrization.py --config config.json --images FOTOS/

# Etiquetar GCPs (pendiente)
python labeling/gcp_labeler.py --images dataset/labeled/raul_deves/images/

# Preparar splits (pendiente)
python dataset/prepare_splits.py --labeled dataset/labeled/ --output dataset/yolo/
```
