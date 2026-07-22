"""
experimento_paralelo.py
Experimento de ejecucion paralela WebODM + NodeODM - IPRE IPI-26-704

Lanza 8 tareas de ortofoto en calidad media (4 sets reales x 2 repeticiones)
desde el maestro WebODM (.80) repartidas explicitamente entre los nodos de
procesamiento NodeODM (.81 y .82), y mide que pasa con la ejecucion en
paralelo: tiempo en cola vs. tiempo de procesamiento real por tarea y por nodo.

Requiere que .81 y .82 ya esten agregados como "Nodos de procesamiento" en el
WebODM maestro (ver nodos/guia_instalación_nodos.md).

Uso:
    # Validar el reparto sin tocar la red (no requiere WebODM levantado)
    python experimento_paralelo.py --config experimento_config.json --modo fija --dry-run
    python experimento_paralelo.py --config experimento_config.json --modo peso --dry-run

    # Correr el experimento de verdad
    python experimento_paralelo.py --config experimento_config.json --modo fija
    python experimento_paralelo.py --config experimento_config.json --modo peso

    # Correr y ademas descargar la ortofoto de cada tarea al terminar
    python experimento_paralelo.py --config experimento_config.json --modo fija --descargar

Dependencias:
    pip install requests
    (usa funciones de webodm_pipeline.py, debe estar en la misma carpeta)
"""

import argparse
import csv
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

import requests

import webodm_pipeline as wp

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")


# ─────────────────────────────────────────────
# Carga de configuracion
# ─────────────────────────────────────────────

def load_config(config_path: str) -> dict:
    path = Path(config_path)
    if not path.exists():
        raise FileNotFoundError(f"No se encontro config: {config_path}")
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    required = ["webodm", "project", "nodos", "sets", "options", "output_dir", "polling"]
    for key in required:
        if key not in config:
            raise KeyError(f"Falta seccion '{key}' en el config JSON")
    if len(config["nodos"]) < 1:
        raise ValueError("El config debe declarar al menos un nodo en 'nodos'")
    return config


# ─────────────────────────────────────────────
# Nodos de procesamiento
# ─────────────────────────────────────────────

def list_processing_nodes(host: str, headers: dict) -> list[dict]:
    """GET /api/processingnodes/ - nodos NodeODM registrados en el maestro."""
    response = requests.get(f"{host}/api/processingnodes/", headers=headers, timeout=30)
    response.raise_for_status()
    data = response.json()
    return data if isinstance(data, list) else data.get("results", [])


def resolver_nodos(host: str, headers: dict, nodos_cfg: list[dict]) -> list[dict]:
    """Empareja los nodos declarados en el config con los registrados en WebODM y valida que existan."""
    disponibles = list_processing_nodes(host, headers)
    resueltos = []
    for n in nodos_cfg:
        match = next((p for p in disponibles if p.get("hostname") == n["hostname"]), None)
        if not match:
            hosts_disponibles = ", ".join(p.get("hostname", "?") for p in disponibles) or "(ninguno)"
            raise ValueError(
                f"Nodo '{n['hostname']}' no esta registrado en WebODM ({host}).\n"
                f"     Registrados actualmente: {hosts_disponibles}\n"
                f"     Agregalo en WebODM > Nodos de procesamiento (ver nodos/guia_instalación_nodos.md)"
            )
        if not match.get("online", True):
            print(f"[!] Aviso: nodo {n['hostname']} figura OFFLINE en este momento en WebODM")
        resueltos.append({**n, "id": match["id"], "queue_count": match.get("queue_count", 0)})
        print(f"[OK] Nodo resuelto: {n['hostname']} -> id={match['id']} (label='{match.get('label','')}', queue_count={match.get('queue_count',0)})")
    return resueltos


# ─────────────────────────────────────────────
# Construccion y reparto de trabajos
# ─────────────────────────────────────────────

def carpeta_tamano_mb(dir_path: str) -> float:
    total = sum(f.stat().st_size for f in Path(dir_path).iterdir() if f.is_file())
    return total / (1024 * 1024)


def construir_trabajos(sets_cfg: list[dict], repeticiones: int) -> list[dict]:
    """Genera la lista de trabajos: cada set del config, repetido N veces como tareas separadas."""
    trabajos = []
    for s in sets_cfg:
        if not Path(s["dir"]).exists():
            raise FileNotFoundError(f"Directorio de fotos no encontrado: {s['dir']}")
        tamano = round(carpeta_tamano_mb(s["dir"]), 1)
        for r in range(1, repeticiones + 1):
            nombre_task = f"exp_{Path(s['dir']).name}_run{r}".replace(" ", "_")
            trabajos.append({
                "set": s["nombre"],
                "dir": s["dir"],
                "run": r,
                "tamano_mb": tamano,
                "task_name": nombre_task,
            })
    return trabajos


def repartir_fija(trabajos: list[dict], nodos: list[dict]) -> list[tuple]:
    """Divide la lista de trabajos en bloques iguales y consecutivos, uno por nodo (ej: primeros 4 -> nodo1, ultimos 4 -> nodo2)."""
    n = len(nodos)
    tam_grupo = -(-len(trabajos) // n)  # division hacia arriba
    resultado = []
    for i, t in enumerate(trabajos):
        idx_nodo = min(i // tam_grupo, n - 1)
        resultado.append((t, nodos[idx_nodo]))
    return resultado


def repartir_por_peso(trabajos: list[dict], nodos: list[dict]) -> list[tuple]:
    """Reparto balanceado por peso (MB) de cada set: algoritmo LPT (Longest Processing Time).
    Ordena los trabajos de mayor a menor tamano y asigna cada uno al nodo con menor carga acumulada."""
    orden = sorted(trabajos, key=lambda t: t["tamano_mb"], reverse=True)
    carga = {n["hostname"]: 0.0 for n in nodos}
    resultado = []
    for t in orden:
        nodo = min(nodos, key=lambda n: carga[n["hostname"]])
        carga[nodo["hostname"]] += t["tamano_mb"]
        resultado.append((t, nodo))
    return resultado


def imprimir_reparto(reparto: list[tuple]):
    print("\n[>>] Plan de reparto:")
    print(f"  {'TAREA':<28} {'SET':<32} {'RUN':<4} {'MB':>8}   NODO")
    print("  " + "-" * 90)
    for t, nodo in reparto:
        print(f"  {t['task_name']:<28} {t['set']:<32} {t['run']:<4} {t['tamano_mb']:>8.1f}   {nodo['hostname']}")
    print()
    for nodo in {nodo["hostname"]: nodo for _, nodo in reparto}.values():
        asignados = [t for t, n in reparto if n["hostname"] == nodo["hostname"]]
        total_mb = sum(t["tamano_mb"] for t in asignados)
        print(f"  [{nodo['hostname']}] {len(asignados)} tareas, {total_mb:.1f} MB totales")
    print()


# ─────────────────────────────────────────────
# Creacion de tareas con nodo forzado
# ─────────────────────────────────────────────

def crear_tarea_en_nodo(host: str, headers: dict, project_id: int, trabajo: dict, nodo: dict, options: dict) -> int:
    """Crea una tarea en WebODM y fuerza que se procese en un nodo especifico
    (processing_node=<id>, auto_processing_node=false), en vez de dejar que
    WebODM elija automaticamente el nodo menos cargado."""
    images = wp.collect_images(trabajo["dir"])
    options_list = [{"name": k, "value": str(v).lower() if isinstance(v, bool) else str(v)} for k, v in options.items()]
    url = f"{host}/api/projects/{project_id}/tasks/"

    files = []
    try:
        for img_path in images:
            files.append(("images", (img_path.name, open(img_path, "rb"), "image/jpeg")))
        data = {
            "name": trabajo["task_name"],
            "options": json.dumps(options_list),
            "processing_node": str(nodo["id"]),
            "auto_processing_node": "false",
        }
        response = requests.post(url, headers=headers, files=files, data=data, timeout=600)
        if not response.ok:
            raise RuntimeError(f"WebODM respondio {response.status_code}: {response.text}")
        return response.json()["id"]
    finally:
        for _, (_, file_obj, _) in files:
            file_obj.close()


def _crear_secuencial_en_nodo(host: str, headers: dict, project_id: int, nodo: dict, trabajos: list[dict], options: dict) -> list[dict]:
    """Crea, en orden, todas las tareas asignadas a UN nodo. No arranca la siguiente
    hasta que la anterior termino de crearse (subida incluida) — asi el orden dentro
    de la cola FIFO de ese NodeODM queda determinado por el orden del reparto, no por
    cual subida termino antes."""
    resultados = []
    for trabajo in trabajos:
        registro = {**trabajo, "nodo": nodo["hostname"]}
        try:
            task_id = crear_tarea_en_nodo(host, headers, project_id, trabajo, nodo, options)
            registro.update(task_id=task_id, hora_creada=datetime.now(), estado="creada", error=None)
            print(f"  [OK] {trabajo['task_name']} -> nodo {nodo['hostname']} (task_id={task_id})")
        except Exception as e:
            registro.update(task_id=None, hora_creada=datetime.now(), estado="error_creacion", error=str(e))
            print(f"  [ERROR] {trabajo['task_name']} -> nodo {nodo['hostname']}: {e}")
        resultados.append(registro)
    return resultados


def lanzar_tareas(host: str, headers: dict, project_id: int, reparto: list[tuple], options: dict) -> list[dict]:
    """Crea las tareas en paralelo ENTRE nodos (un hilo por nodo), pero en orden
    DENTRO de cada nodo (respeta el orden del reparto). Esto refleja como NodeODM
    procesa en realidad: cola FIFO de a una por nodo (ver parallel_queue_processing)."""
    por_nodo: dict = {}
    for trabajo, nodo in reparto:
        entrada = por_nodo.setdefault(nodo["hostname"], {"nodo": nodo, "trabajos": []})
        entrada["trabajos"].append(trabajo)

    print(f"[>>] Creando {len(reparto)} tareas: {len(por_nodo)} nodo(s) en paralelo, orden respetado dentro de cada nodo...")
    resultados = []
    with ThreadPoolExecutor(max_workers=len(por_nodo)) as executor:
        futuros = [
            executor.submit(_crear_secuencial_en_nodo, host, headers, project_id, info["nodo"], info["trabajos"], options)
            for info in por_nodo.values()
        ]
        for futuro in as_completed(futuros):
            resultados.extend(futuro.result())
    return resultados


# ─────────────────────────────────────────────
# Monitoreo paralelo
# ─────────────────────────────────────────────

def consultar_estado(host: str, headers: dict, project_id: int, task_id: int) -> dict:
    url = f"{host}/api/projects/{project_id}/tasks/{task_id}/"
    response = requests.get(url, headers=headers, timeout=30)
    response.raise_for_status()
    return response.json()


def monitorear(host: str, headers: dict, project_id: int, tareas: list[dict], polling_cfg: dict, csv_path: Path):
    interval = polling_cfg["interval_seconds"]
    timeout_minutes = polling_cfg["timeout_minutes"]
    max_checks = (timeout_minutes * 60) // interval

    activas = [t for t in tareas if t["task_id"] is not None]
    print(f"\n[>>] Monitoreando {len(activas)} tareas (polling cada {interval}s, timeout {timeout_minutes} min)...")

    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        csv.writer(f).writerow([
            "timestamp", "task_name", "set", "run", "nodo", "task_id",
            "estado", "progreso_pct", "tamano_mb"
        ])

    for i in range(int(max_checks)):
        pendientes = 0
        with open(csv_path, "a", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            for t in activas:
                if t["estado"] in ("completada", "fallida", "cancelada", "timeout"):
                    continue
                try:
                    task = consultar_estado(host, headers, project_id, t["task_id"])
                except requests.RequestException as e:
                    print(f"  [!] Error consultando {t['task_name']}: {e}")
                    continue

                status = task["status"]
                progreso = round(task.get("running_progress", 0.0) * 100, 1)
                label = wp.STATUS_LABELS.get(status, f"Estado {status}")

                if status == 20 and t.get("hora_running") is None:
                    t["hora_running"] = datetime.now()
                if status == 40:
                    t["estado"] = "completada"
                    t["hora_fin"] = datetime.now()
                elif status in (30, 50):
                    t["estado"] = "fallida" if status == 30 else "cancelada"
                    t["hora_fin"] = datetime.now()
                    t["error"] = task.get("last_error", "Sin detalle")
                else:
                    t["estado"] = label.lower()
                    pendientes += 1

                writer.writerow([
                    datetime.now().isoformat(timespec="seconds"), t["task_name"], t["set"], t["run"],
                    t["nodo"], t["task_id"], t["estado"], progreso, t["tamano_mb"]
                ])

        resumen = "  ".join(f"{t['task_name']}[{t['nodo']}]:{t['estado']}" for t in activas)
        print(f"  [{i+1:>3}] {resumen}")

        if pendientes == 0:
            print("[OK] Todas las tareas activas terminaron (completadas, fallidas o canceladas).")
            break
        time.sleep(interval)
    else:
        print(f"[!] Timeout de {timeout_minutes} min alcanzado con tareas aun en curso.")
        for t in activas:
            if t["estado"] not in ("completada", "fallida", "cancelada"):
                t["estado"] = "timeout"


def imprimir_resumen(tareas: list[dict]):
    print("\n" + "=" * 100)
    print("RESUMEN DEL EXPERIMENTO")
    print("=" * 100)
    print(f"{'TAREA':<28} {'NODO':<16} {'ESTADO':<12} {'COLA (min)':>11} {'PROCESO (min)':>14} {'TOTAL (min)':>12}")
    for t in tareas:
        creada = t.get("hora_creada")
        running = t.get("hora_running")
        fin = t.get("hora_fin")
        cola = (running - creada).total_seconds() / 60 if creada and running else None
        proceso = (fin - running).total_seconds() / 60 if running and fin else None
        total = (fin - creada).total_seconds() / 60 if creada and fin else None
        fmt = lambda v: f"{v:.1f}" if v is not None else "-"
        print(f"{t['task_name']:<28} {t.get('nodo','-'):<16} {t.get('estado','-'):<12} {fmt(cola):>11} {fmt(proceso):>14} {fmt(total):>12}")

    print("\nPor nodo:")
    nodos = sorted({t["nodo"] for t in tareas if t.get("nodo")})
    for nodo in nodos:
        del_nodo = [t for t in tareas if t.get("nodo") == nodo]
        colas = [(t["hora_running"] - t["hora_creada"]).total_seconds() / 60 for t in del_nodo if t.get("hora_creada") and t.get("hora_running")]
        procesos = [(t["hora_fin"] - t["hora_running"]).total_seconds() / 60 for t in del_nodo if t.get("hora_running") and t.get("hora_fin")]
        creadas = [t["hora_creada"] for t in del_nodo if t.get("hora_creada")]
        fines = [t["hora_fin"] for t in del_nodo if t.get("hora_fin")]
        ventana_total = (max(fines) - min(creadas)).total_seconds() / 60 if creadas and fines else None
        print(f"  [{nodo}] {len(del_nodo)} tareas | cola promedio: {sum(colas)/len(colas):.1f} min" if colas else f"  [{nodo}] {len(del_nodo)} tareas | cola promedio: -", end="")
        print(f" | proceso promedio: {sum(procesos)/len(procesos):.1f} min" if procesos else " | proceso promedio: -", end="")
        print(f" | ventana total del nodo: {ventana_total:.1f} min" if ventana_total else " | ventana total del nodo: -")
    print("=" * 100)


# ─────────────────────────────────────────────
# Descarga opcional
# ─────────────────────────────────────────────

def descargar_completadas(host: str, headers: dict, project_id: int, tareas: list[dict], output_dir: str):
    for t in tareas:
        if t.get("estado") != "completada":
            continue
        out = Path(output_dir) / t["task_name"]
        out.mkdir(parents=True, exist_ok=True)
        print(f"\n[>>] Descargando ortofoto de {t['task_name']}...")
        wp.download_asset(host, headers, project_id, t["task_id"], "orthophoto_tif", out)


# ─────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(
        description="Experimento de ejecucion paralela WebODM + NodeODM (.81/.82) - IPRE IPI-26-704"
    )
    parser.add_argument("--config", required=True, help="Ruta al experimento_config.json")
    parser.add_argument("--modo", choices=["fija", "peso"], default="fija",
                         help="'fija': bloques iguales por orden (ej. 4 y 4). 'peso': balanceo por MB de cada set (LPT)")
    parser.add_argument("--dry-run", action="store_true", help="Solo calcula y muestra el reparto, no toca la red")
    parser.add_argument("--descargar", action="store_true", help="Descarga la ortofoto de cada tarea completada")
    return parser.parse_args()


def main():
    args = parse_args()
    print(f"[>>] Leyendo configuracion: {args.config}")
    config = load_config(args.config)

    trabajos = construir_trabajos(config["sets"], config.get("repeticiones", 1))
    print(f"[OK] {len(trabajos)} trabajos construidos ({len(config['sets'])} sets x {config.get('repeticiones',1)} repeticiones)")

    if args.dry_run:
        nodos_placeholder = [{"hostname": n["hostname"], "id": "?"} for n in config["nodos"]]
        reparto = repartir_fija(trabajos, nodos_placeholder) if args.modo == "fija" else repartir_por_peso(trabajos, nodos_placeholder)
        imprimir_reparto(reparto)
        print("[OK] Dry-run: no se contacto a WebODM ni se subio nada.")
        sys.exit(0)

    token = wp.get_token(config["webodm"]["host"], config["webodm"]["username"], config["webodm"]["password"])
    headers = wp.auth_headers(token)
    host = config["webodm"]["host"]

    nodos = resolver_nodos(host, headers, config["nodos"])
    project_id = wp.get_or_create_project(host, headers, config["project"]["name"], config["project"].get("description", ""))

    reparto = repartir_fija(trabajos, nodos) if args.modo == "fija" else repartir_por_peso(trabajos, nodos)
    imprimir_reparto(reparto)

    hora_inicio = datetime.now()
    tareas = lanzar_tareas(host, headers, project_id, reparto, config["options"])

    csv_path = Path(config["output_dir"]) / f"log_experimento_{args.modo}_{hora_inicio.strftime('%Y%m%d_%H%M%S')}.csv"
    monitorear(host, headers, project_id, tareas, config["polling"], csv_path)

    imprimir_resumen(tareas)
    print(f"\n[OK] Log detallado guardado en: {csv_path}")

    if args.descargar:
        descargar_completadas(host, headers, project_id, tareas, config["output_dir"])

    print("\n[LISTO] Experimento terminado.")


if __name__ == "__main__":
    main()
