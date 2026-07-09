# Referencia de parámetros ODM — IPRE IPI-26-704

Todos los parámetros que se pueden configurar en la sección `"options"` del `config.json`.  
Los valores marcados con ★ son los más relevantes para este proyecto.

---

## Control de pipeline

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `end-with` | enum | `odm_postprocess` | Detiene el procesamiento en esta etapa. Valores: `dataset`, `split`, `merge`, `opensfm`, `openmvs`, `odm_filterpoints`, `odm_meshing`, `mvs_texturing`, `odm_georeferencing`, `odm_dem`, `odm_orthophoto`, `odm_report`, `odm_postprocess` |
| `rerun-from` | enum | _(vacío)_ | Reinicia desde esta etapa (mismos valores que `end-with`). Útil para no reprocesar desde cero |

---

## Extracción de características ★

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `min-num-features` ★ | int | `10000` | Mínimo de features por imagen. Más features = más emparejamientos posibles pero más lento |
| `feature-type` | enum | `dspsift` | Algoritmo de detección. Valores: `akaze`, `dspsift`, `hahog`, `orb`, `sift` |
| `feature-quality` ★ | enum | `high` | Calidad de extracción: `ultra`, `high`, `medium`, `low`, `lowest`. Cada paso sube el tiempo considerablemente |

---

## Matching (emparejamiento entre imágenes)

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `matcher-type` | enum | `flann` | Algoritmo de matching: `bow` (rápido), `flann` (estable), `bruteforce` (lento y robusto) |
| `matcher-neighbors` | int | `0` | Empareja con las N imágenes más cercanas según GPS EXIF. `0` = por triangulación |
| `matcher-order` | int | `0` | Empareja con las N imágenes más cercanas por nombre de archivo. Útil para video |

---

## Cámara y calibración

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `camera-lens` | enum | `auto` | Tipo de lente: `auto`, `perspective`, `brown`, `fisheye`, `fisheye_opencv`, `spherical`, `equirectangular`, `dual` |
| `use-fixed-camera-params` | bool | `false` | No optimiza parámetros de cámara. Puede ayudar con efecto doming/bowling |
| `cameras` | string | _(vacío)_ | Ruta a un `cameras.json` con parámetros de cámara precalculados |
| `radiometric-calibration` | enum | `none` | Para multiespectral/térmica: `none`, `camera`, `camera+sun` |
| `rolling-shutter` | bool | `false` | Corrección de rolling shutter (cámaras en movimiento) |
| `rolling-shutter-readout` | float | `0` | Tiempo de lectura del sensor en ms. `0` = usar base de datos interna |

---

## Structure from Motion (SfM)

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `sfm-algorithm` | enum | `incremental` | Algoritmo SfM: `incremental` (general), `triangulation` (con GPS+ángulos), `planar` (vuelos nadirales a altitud fija, muy rápido) |
| `sfm-no-partial` | bool | `false` | No intenta unir reconstrucciones parciales |
| `use-hybrid-bundle-adjustment` | bool | `false` | Ajuste local por imagen + global cada 100 imgs. Acelera datasets muy grandes |
| `max-concurrency` | int | `16` | Número máximo de procesos paralelos. ~1 GB de RAM por hilo |
| `sky-removal` | bool | `false` | Enmascara el cielo automáticamente con IA (experimental) |
| `bg-removal` | bool | `false` | Enmascara el fondo automáticamente con IA (experimental) |

---

## Nube de puntos ★

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `pc-quality` ★ | enum | `medium` | Calidad: `ultra`, `high`, `medium`, `low`, `lowest`. Cada nivel multiplica el tiempo ~4x |
| `pc-filter` | float | `5` | Filtra puntos que se desvían más de N desviaciones estándar. `0` = sin filtro |
| `pc-sample` | float | `0` | Mantiene un solo punto por radio N metros. `0` = sin muestreo |
| `pc-classify` | bool | `false` | Clasifica la nube (suelo/vegetación/edificios) con filtro morfológico |
| `pc-skip-geometric` | bool | `false` | Deshabilita estimaciones geométricas (útil en datasets muy grandes) |
| `pc-las` | bool | `false` | Exporta nube en formato `.las` además del `.laz` por defecto |
| `pc-csv` | bool | `false` | Exporta nube en formato `.csv` |
| `pc-ept` | bool | `false` | Exporta en formato Entwine Point Tile (para viewers web) |
| `pc-copc` | bool | `false` | Exporta en Cloud Optimized Point Cloud (COPC) |

### Filtro morfológico simple (SMRF) — para DTM

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `smrf-scalar` | float | `1.25` | Parámetro escalar de elevación |
| `smrf-slope` | float | `0.15` | Pendiente (rise over run) |
| `smrf-threshold` | float | `0.5` | Umbral de elevación en metros |
| `smrf-window` | float | `18` | Radio de ventana en metros |

---

## Malla 3D ★

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `mesh-size` ★ | int | `200000` | Máximo de vértices de la malla de salida |
| `mesh-octree-depth` ★ | int | `11` | Profundidad del octree (1–14). Más = más detalle. Recomendado: 8–12 |
| `use-3dmesh` ★ | bool | `false` | Usa malla 3D completa para generar la ortofoto en vez de una 2.5D |
| `skip-3dmodel` | bool | `false` | Omite la generación del modelo 3D. Ahorra tiempo si solo necesitas ortofoto/DEM |
| `fast-orthophoto` | bool | `false` | Genera ortofoto directamente desde la reconstrucción sparse (sin MVS). Mucho más rápido, menor calidad |

### Texturizado

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `texturing-skip-global-seam-leveling` | bool | `false` | Omite normalización de colores entre imágenes. Útil para datos radiométricos |
| `texturing-keep-unseen-faces` | bool | `false` | Conserva caras de la malla no visibles en ninguna cámara |
| `texturing-single-material` | bool | `false` | Genera un solo material/textura en vez de múltiples |
| `gltf` | bool | `false` | Genera modelos glTF binario (.glb) con texturas |

---

## DEM: DSM y DTM ★

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `dsm` ★ | bool | `false` | Genera DSM (Digital Surface Model: suelo + objetos) |
| `dtm` ★ | bool | `false` | Genera DTM (Digital Terrain Model: solo suelo) |
| `dem-resolution` ★ | float | `5` | Resolución del DEM en cm/pixel (limitada por GSD estimado) |
| `dem-gapfill-steps` | int | `3` | Pasos para rellenar huecos en el DEM con IDW. `0` = sin relleno |
| `dem-decimation` | int | `1` | Decima la nube antes de generar el DEM. `1` = sin decimación, `100` ≈ 99% menos puntos |
| `dem-euclidean-map` | bool | `false` | Genera mapa euclidiano de distancia a NODATA para cada DEM |

---

## Ortofoto ★

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `orthophoto-resolution` ★ | float | `5` | GSD en cm/pixel. Valores menores = más detalle y mayor archivo |
| `orthophoto-compression` | enum | `DEFLATE` | Compresión del GeoTIFF: `JPEG`, `LZW`, `PACKBITS`, `DEFLATE`, `LZMA`, `NONE` |
| `orthophoto-png` | bool | `false` | Genera además una copia en formato PNG |
| `orthophoto-kmz` | bool | `false` | Genera una copia en formato KMZ para Google Earth |
| `orthophoto-no-tiled` | bool | `false` | GeoTIFF en franjas en vez de teselado. No recomendado |
| `orthophoto-cutline` | bool | `false` | Polígono de recorte para mosaicos sin costuras |
| `skip-orthophoto` | bool | `false` | Omite la generación de la ortofoto |

---

## Formatos de salida adicionales

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `cog` | bool | `false` | Cloud-Optimized GeoTIFF (mejor para visualizadores web) |
| `tiles` | bool | `false` | Tiles estáticos para Leaflet / OpenLayers |
| `3d-tiles` | bool | `false` | OGC 3D Tiles |
| `build-overviews` | bool | `false` | Overviews para visualización rápida en QGIS/Civil 3D |

---

## Georreferenciación

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `use-exif` | bool | `false` | Usa GPS del EXIF aunque exista `gcp_list.txt` |
| `force-gps` | bool | `false` | Usa GPS del EXIF para la reconstrucción aunque haya GCPs |
| `gps-accuracy` ★ | float | `3` | DOP de GPS en metros. Bajar este valor si tienes GPS RTK de alta precisión |
| `gps-z-offset` | float | `0` | Offset vertical en metros (útil para pasar de altitud elipsoidal a ortométrica) |

---

## Área de procesamiento

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `crop` | float | `3` | Recorta los outputs N metros hacia adentro del borde. `0` = sin recorte |
| `boundary` | string | _(vacío)_ | GeoJSON que define el área de reconstrucción |
| `auto-boundary` | bool | `false` | Define el boundary automáticamente desde las posiciones GPS de las cámaras |
| `auto-boundary-distance` | float | `0` | Distancia extra desde las cámaras al borde del boundary. `0` = automático |

---

## Rendimiento y disco

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `ignore-gsd` | bool | `false` | Ignora el GSD estimado. Puede mejorar la calidad pero usa mucha más RAM. **No usar salvo necesidad específica** |
| `no-gpu` | bool | `false` | Deshabilita aceleración GPU aunque esté disponible |
| `optimize-disk-space` | bool | `false` | Borra archivos intermedios pesados para ahorrar disco. Impide reanudar el pipeline desde etapas intermedias |

---

## Split-Merge (datasets grandes)

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `split` | int | `999999` | Imágenes por submodelo. Bajar a 200–500 para datasets masivos |
| `split-overlap` | float | `150` | Radio de solapamiento entre submodelos en metros |
| `sm-no-align` | bool | `false` | Omite alineación de submodelos. Útil si el GPS es muy preciso |
| `sm-cluster` | string | `None` | URL de ClusterODM para distribuir el procesamiento en varios nodos |
| `merge` | enum | `all` | Qué fusionar en el paso merge: `all`, `pointcloud`, `orthophoto`, `dem` |

---

## Multiespectral y térmica

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `primary-band` | string | `auto` | Banda principal para la reconstrucción en datasets multiespectrales |
| `skip-band-alignment` | bool | `false` | Omite la alineación de bandas si ya están prealineadas |

---

## Video

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `video-limit` | int | `500` | Máximo de frames a extraer del video. `0` = sin límite |
| `video-resolution` | int | `4000` | Resolución máxima de los frames extraídos en pixels |

---

## Reporte

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `skip-report` | bool | `false` | Omite la generación del PDF de calidad |

---

## Uso del script con presets y flags

### Ver presets disponibles en WebODM

```bash
python webodm_pipeline.py --config config.json --list-presets
```

### Usar un preset directamente (reemplaza `options` del config)

```bash
# Testeo rápido
python webodm_pipeline.py --config config.json --preset "Fast Orthophoto"

# Producción con DSM y DTM
python webodm_pipeline.py --config config.json --preset "DSM + DTM"

# Modelo 3D
python webodm_pipeline.py --config config.json --preset "3D Model"

# Alta resolución
python webodm_pipeline.py --config config.json --preset "High Resolution"
```

### Lanzar sin esperar (deja el remoto procesando solo)

```bash
python webodm_pipeline.py --config config.json --preset "Fast Orthophoto" --no-wait

python webodm_pipeline.py --config config.json --no-wait
```

### Apuntar a otro directorio de fotos sin editar el config

```bash
python webodm_pipeline.py --config config.json --images ./FOTOS/06.-\ Edificio\ C --no-wait

python webodm_pipeline.py --config config.json --images ./FOTOS/06.-\ Edificio\ C --preset "High Resolution" --no-wait
```

### Validar config sin enviar nada

```bash
python webodm_pipeline.py --config config.json --dry-run
```

### Descargar resultados de una tarea ya completada

```bash
# El script imprime TASK_ID y PROJECT_ID al lanzar con --no-wait
python webodm_pipeline.py --config config.json --download 7 --project-id 3
```

---

## Configuraciones rápidas de referencia

```json
// Prototipo rápido (exploración)
{
  "feature-quality": "low",
  "pc-quality": "low",
  "orthophoto-resolution": 10,
  "skip-3dmodel": true,
  "fast-orthophoto": true
}

// Producción estándar (campus UC)
{
  "feature-quality": "high",
  "pc-quality": "high",
  "orthophoto-resolution": 5,
  "dsm": true,
  "dtm": true,
  "use-3dmesh": true,
  "mesh-octree-depth": 11,
  "mesh-size": 200000,
  "cog-geotiff": true
}

// Alta calidad (entregable final)
{
  "feature-quality": "ultra",
  "pc-quality": "ultra",
  "orthophoto-resolution": 2,
  "dsm": true,
  "dtm": true,
  "mesh-octree-depth": 13,
  "build-overviews": true,
  "cog": true
}
```
