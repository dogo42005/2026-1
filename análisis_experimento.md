# Análisis del experimento de ejecución paralela WebODM + NodeODM

**Proyecto:** IPRE IPI-26-704 — Detector de GCPs en Imágenes UAV
**Fecha:** julio 2026
**Infraestructura:** 1 maestro WebODM (`.80`) + 2 nodos de procesamiento NodeODM (`.81`, `.82`)

## 1. Objetivo

Evaluar qué ocurre al procesar varias ortofotos en paralelo repartidas entre dos nodos de
procesamiento (`.81` y `.82`), comparando dos estrategias de reparto de carga, y medir el
efecto de esa estrategia sobre el tiempo total del lote.

## 2. Arquitectura

```
WebODM maestro (.80, puerto 8000)
   │  crea tareas, sube fotos, asigna nodo de procesamiento
   ├── NodeODM .81 (puerto 3000)
   └── NodeODM .82 (puerto 3000)
```

- El maestro y los nodos corren NodeODM/WebODM sobre Docker dentro de WSL2, con
  `networkingMode=mirrored` para exponer los puertos a la LAN.
- Cada NodeODM procesa **una tarea a la vez por defecto** (`parallel_queue_processing = 1`,
  ver `nodos/nodos.md`). Cualquier tarea adicional asignada al mismo nodo queda en estado
  `QUEUED` hasta que la anterior termina — el paralelismo real de este montaje es **2 vías**
  (una por nodo), no N vías por más tareas que se envíen.

## 3. Método

Script: [`experimento_paralelo.py`](experimento_paralelo.py), configs
[`experimento_config.json`](experimento_config.json) y
[`experimento_config_pesados.json`](experimento_config_pesados.json).

- **Asignación forzada de nodo:** cada tarea se crea con `processing_node=<id>` y
  `auto_processing_node=false` vía la API REST de WebODM, en vez de dejar que WebODM elija
  automáticamente el nodo menos cargado.
- **Dos estrategias de reparto:**
  - `fija`: bloques consecutivos según el orden de la lista de sets (ej. primeros 4 → `.81`,
    últimos 4 → `.82`).
  - `peso`: algoritmo LPT (*Longest Processing Time*) — ordena los trabajos de mayor a menor
    tamaño (MB de la carpeta) y asigna cada uno al nodo con menor carga acumulada hasta ese
    momento, buscando que ambos nodos terminen con el mismo total de MB.
- **Creación de tareas:** paralela *entre* nodos (un hilo por nodo, ambos arrancan a la vez),
  pero secuencial *dentro* de cada nodo — respeta el orden del reparto y refleja la cola FIFO
  real de NodeODM.
- **Calidad:** `feature-quality: medium`, `pc-quality: medium`, `orthophoto-resolution: 5`,
  sin malla 3D ni DSM/DTM (solo ortofoto, para acotar el tiempo por tarea).
- **Métricas registradas por tarea:** tiempo en cola (creación → inicio real de
  procesamiento), tiempo de proceso (inicio real → fin), tiempo total, y por nodo: promedio de
  cola/proceso y "ventana total" (desde que arranca su primera tarea hasta que termina la
  última).

## 4. Datos usados

6 sets reales de fotos UAV en `FOTOS/`, de 241 MB a 1561 MB. Se corrieron dos experimentos
independientes de 8 tareas cada uno (repitiendo sets para completar el lote, dado que solo
había 6 sets distintos disponibles):

| Experimento | Sets | Repeticiones | Tareas |
|---|---|---|---|
| **Livianos** | 03 (241 MB), 02 (461.9 MB), 04 (514.6 MB), 01 (536.3 MB) | x2 c/u | 8 |
| **Pesados** | 05 (549.8 MB), 06 (1561.3 MB, 159 fotos) | x4 c/u | 8 |

## 5. Incidente operativo durante el experimento

A mitad de sesión, WebODM reportó el nodo `.82` como `offline`, aunque el contenedor
`nodeodm` seguía `Up` y sus logs mostraban `Server has started on port 3000`. Diagnóstico
paso a paso:

1. **Descartado:** el contenedor y Docker estaban sanos (`docker ps`, `docker logs`,
   `systemctl status docker` todo OK).
2. **Primer sospechoso (descartado tras corregirlo):** una regla de `portproxy` en `.82`
   reenviaba `0.0.0.0:3000` hacia `146.155.38.82:3000` — es decir, hacia sí misma, un
   remanente de cuando esa PC no estaba en modo `mirrored`. Se eliminó, pero el nodo seguía
   sin responder desde `.80`.
3. **Causa raíz real:** `docker port nodeodm` no devolvía ningún mapeo, y ni siquiera desde
   *dentro* de WSL2 (`wsl -- curl localhost:3000`) respondía. El contenedor se había
   levantado **sin `-p 3000:3000`** — NodeODM escuchaba el puerto solo puertas adentro del
   contenedor, nunca publicado hacia el host.
4. **Solución:** recrear el contenedor con el mapeo de puerto correcto
   (`docker run -d --name nodeodm --restart always -p 3000:3000 opendronemap/nodeodm`).

**Lección operativa:** un nodo "offline" en WebODM no implica necesariamente que el proceso
esté caído — puede estar sano puertas adentro y simplemente no publicado hacia afuera.
`docker port <contenedor>` es un chequeo más concluyente que mirar logs o el estado del
contenedor.

## 6. Resultados

| Experimento | Modo | Reparto de MB (`.81` / `.82`) | Ventana `.81` | Ventana `.82` | Tiempo total del lote |
|---|---|---|---|---|---|
| Livianos | `fija` | 1405.8 / 2101.8 MB | 14.7 min | 23.6 min | **~25 min** |
| Livianos | `peso` | 1753.8 / 1753.8 MB | 22.1 min | 19.7 min | **~22 min** |
| Pesados | `fija` | 2199.2 / 6245.2 MB | 21.8 min | 61.6 min | **~62 min** |
| Pesados | `peso` | 4222.2 / 4222.2 MB | 41.5 min | 42.3 min | **~42 min** |

*(Ventana = desde que arranca la primera tarea del nodo hasta que termina la última. Logs
completos en `outputs/experimento_paralelo/` y `outputs/experimento_paralelo_pesados/`.)*

En el experimento de sets pesados, el caso más extremo de `fija` fue la última tarea
asignada a `.82` (4ª copia del set de 159 fotos): esperó **42.3 minutos en cola** solo por
estar detrás de las otras 3 copias del mismo set pesado en el mismo nodo — algo que el
reparto por peso evita por diseño, al no apilar los trabajos más grandes en un solo nodo.

## 7. Conclusión

1. **El paralelismo real de este montaje es de 2 vías, no 8.** Cada NodeODM procesa una
   tarea a la vez por defecto; asignar más tareas a un mismo nodo no las paraleliza entre sí,
   solo las encola. El verdadero paralelismo ocurre *entre* `.81` y `.82`, no dentro de cada
   uno.

2. **La estrategia de reparto sí afecta el tiempo total del lote, y el efecto crece con el
   desbalance de los datos.** En ambos experimentos, `peso` terminó igual o más rápido que
   `fija`:
   - Con sets de tamaño relativamente parecido (livianos), la ventaja fue modesta (~12%,
     25→22 min), porque incluso el reparto "fijo" quedó medianamente parejo.
   - Con sets de tamaño muy desigual (pesados: un set 3x más grande que el otro), la ventaja
     fue grande (~32%, 62→42 min), porque `fija` apiló las 4 copias del set más pesado en un
     solo nodo, dejándolo como cuello de botella mientras el otro nodo terminaba temprano y
     quedaba ocioso.

3. **Recomendación práctica:** cuando los sets a procesar tienen tamaños muy dispares, usar
   reparto por peso (`--modo peso`) en vez de un reparto fijo por bloques. Si en el futuro se
   necesita paralelismo real *dentro* de un mismo nodo (no solo entre nodos), habría que subir
   `parallel_queue_processing` (`-q`) al levantar el contenedor NodeODM — evaluando antes si
   el hardware de `.81`/`.82` soporta correr más de una reconstrucción fotogramétrica
   simultánea sin degradar el tiempo por tarea.

4. **Recomendación operativa:** al diagnosticar un nodo NodeODM "caído", verificar
   `docker port <contenedor>` además de logs y estado del contenedor — la causa puede ser un
   contenedor sano pero sin el puerto publicado hacia el host, invisible en los chequeos
   habituales.
