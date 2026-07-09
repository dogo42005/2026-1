# IPRE IPI-26-704 — Contexto del Proyecto

## Estudiante
Diego Jesús Olivares Pérez  
Licenciatura en Ingeniería en Ciencia de Datos — Instituto de Ingeniería Matemática y Computacional, PUC  
5to semestre — correo: diegoolivares42005@estudiante.uc.cl

## Profesor guía
José Isaac Lemus Romani — Escuela de Construcción Civil UC  
Director de investigación: Harrison Mesa Hernández

## El proyecto
**Título oficial:** Captura de patologías mediante UAV (Drones) en Pavimentos.  
**Línea:** IPI-26-704  
**Duración formal:** 09/07/2026 – 14/08/2026 (120 horas)  
**Modalidad:** Híbrida (Escuela de Construcción Civil UC + Online)  
**Trabajo preparatorio:** desde junio 2026

## Objetivo general
Desarrollar un algoritmo de aprendizaje profundo (YOLOv8) capaz de detectar automáticamente GCPs en imágenes aéreas capturadas por UAV, para reducir el trabajo manual en el flujo fotogramétrico y optimizar el proceso de georreferenciación.

## Objetivos específicos
- **OE1:** Construir dataset etiquetado de imágenes UAV con GCPs anotados en formato YOLO
- **OE2:** Implementar y entrenar YOLOv8, evaluar con precisión / recall / F1-score
- **OE3:** Explorar conceptualmente la integración del modelo en el flujo WebODM/ODM

## ¿Qué es un GCP?
Un Ground Control Point es una marca física en el terreno (tablero de ajedrez blanco/negro, ~50×50 cm) cuyas coordenadas GPS se miden con precisión centimétrica (GNSS diferencial). Se usan en fotogrametría para georreferenciar el modelo con error 2–5 cm en vez de 2–5 m.

En WebODM se ingresan como `gcp_list.txt`:
```
EPSG:32719
Este  Norte  Elevacion  nombre_GCP  foto.JPG  pixel_x  pixel_y
```

## Software del flujo fotogramétrico

| Software | Rol |
|---|---|
| WebODM (`localhost:8000`, Docker) | UI + orquestador: recibe JPGs, genera entregables |
| OpenDroneMap (ODM) | Engine: features → matching → SfM → MVS → DEM → orthophoto |
| Autodesk Civil 3D | Importa ortofoto TIF vía Geoubicación |
| Autodesk ReCap Pro | Visualiza nubes de puntos `.las` / `.rcp` |

## Lo que ya existe

| Archivo | Estado | Descripción |
|---|---|---|
| `webodm_pipeline.py` | ✓ Hecho | Script principal: autentica JWT, crea proyecto, sube imágenes, polling, descarga entregables |
| `config.json` | ✓ Hecho | Config base WebODM/ODM (parámetros de procesamiento) |
| `README.md` | ✓ Hecho | Documentación de uso del pipeline |
| `dataset/exploracion_fotos.py` | Pendiente | Script EXIF + detección GCP por set |
| `dataset/multi_parametrization.py` | Pendiente | Genera configs variando parámetros y lanza tareas |
| `labeling/gcp_labeler.py` | Pendiente | Herramienta interactiva OpenCV para etiquetar GCPs |
| `dataset/prepare_splits.py` | Pendiente | Crea estructura YOLO y splits train/val/test |

## Sets de fotos disponibles (en `FOTOS/`)
- `03.- Edificio Raúl Devés` — ya procesado en WebODM (ortofoto generada)
- `06.- Edificio C - DroneDeploy` — pendiente de procesar
- Otros sets pendientes de explorar (ECCUC, Enfermería, grillas de inspección)

## Datos disponibles en SharePoint prof. Lemus
- **02.- Fotos:** imágenes RAW de vuelos del campus UC (fuente para OE1)
- **03.- Ortofotografías:** 5 ortofotos ya procesadas (.tif, 215–540 MB c/u)
- **02.- Grillas de inspección:** 4 sets de inspección de fachadas/techumbre
- **04.- Nubes de Puntos:** Piscina GR (.rcp)
- **05.- Modelos 3D:** archivos .3sm (ReCap Photo)

## Parámetros clave de procesamiento (config.json actual)

| Parámetro | Valor actual | Descripción |
|---|---|---|
| `orthophoto-resolution` | 5 | GSD en cm/px (5 = 5cm/px) |
| `pc-quality` | high | Calidad nube de puntos |
| `feature-quality` | high | Detección de features |
| `dsm` / `dtm` | true | Modelos de elevación |
| `use-3dmesh` | true | Modelo 3D OBJ |
| `mesh-octree-depth` | 11 | Detalle de la malla |

## Formato de etiqueta YOLO
Un archivo `.txt` por imagen con una línea por GCP:
```
<class_id> <x_center> <y_center> <width> <height>
```
Todos los valores normalizados a [0,1]. Clase única: `0 = gcp`.

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

## Plan de trabajo semanal

| Semana | Fecha | Actividad | Estado |
|---|---|---|---|
| 1 | 23–30 jun | WebODM instalado, script pipeline, diagrama de flujo | En progreso |
| 2 | 30 jun–7 jul | Ortofotos de todos los sets, comparación de parametrizaciones | Pendiente |
| 3 | 7–14 jul | Construcción dataset, etiquetado manual de GCPs | Pendiente |
| 4 | 14–21 jul | Implementación y entrenamiento YOLOv8 | Pendiente |
| 5 | 21–28 jul | Evaluación, integración conceptual WebODM, informe final | Pendiente |

## Pendiente para el 30/06
- [ ] Generar ortofotos/nubes/modelos 3D de TODOS los sets en `FOTOS/`
- [ ] Evaluar comparativamente distintas parametrizaciones
- [ ] Verificar si los sets tienen GCPs visibles (tableros de ajedrez en el suelo)
- [ ] Crear `dataset/multi_parametrization.py`
- [ ] Crear `dataset/exploracion_fotos.py`
