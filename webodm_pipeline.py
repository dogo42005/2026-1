"""
webodm_pipeline.py
Pipeline fotogramétrico automatizado para IPRE IPI-26-704
Lanza tareas en WebODM vía API REST, lee parámetros desde config.json

Uso:
    python webodm_pipeline.py --config config.json
    python webodm_pipeline.py --config config.json --images ./fotos_raul_deves

Dependencias:
    pip install requests tqdm pathlib
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

import requests
from tqdm import tqdm


# ─────────────────────────────────────────────
# Carga de configuración
# ─────────────────────────────────────────────

def load_config(config_path: str) -> dict:
    """Lee el archivo .json y valida campos obligatorios."""
    path = Path(config_path)
    if not path.exists():
        raise FileNotFoundError(f"No se encontró config: {config_path}")
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    required = ["webodm", "project", "task", "options", "exports"]
    for key in required:
        if key not in config:
            raise KeyError(f"Falta sección '{key}' en el config JSON")
    return config


# ─────────────────────────────────────────────
# Autenticación
# ─────────────────────────────────────────────

def get_token(host: str, username: str, password: str) -> str:
    """Obtiene token JWT de WebODM."""
    url = f"{host}/api/token-auth/"
    response = requests.post(url, data={"username": username, "password": password}, timeout=30)
    if response.status_code != 200:
        raise ConnectionError(f"Error de autenticación: {response.status_code} - {response.text}")
    token = response.json().get("token")
    print(f"[OK] Autenticado en WebODM ({host})")
    return token


def auth_headers(token: str) -> dict:
    return {"Authorization": f"JWT {token}"}


# ─────────────────────────────────────────────
# Presets
# ─────────────────────────────────────────────

def list_presets(host: str, headers: dict) -> list[dict]:
    """Devuelve la lista de presets disponibles en WebODM."""
    response = requests.get(f"{host}/api/presets/", headers=headers, timeout=30)
    response.raise_for_status()
    data = response.json()
    return data if isinstance(data, list) else data.get("results", [])


def get_preset_options(host: str, headers: dict, preset_name: str) -> dict:
    """Busca un preset por nombre y retorna sus opciones como dict {nombre: valor}."""
    presets = list_presets(host, headers)
    nombres = [p["name"] for p in presets]
    for preset in presets:
        if preset["name"].lower() == preset_name.lower():
            opciones = {opt["name"]: opt["value"] for opt in preset["options"]}
            print(f"[OK] Preset '{preset['name']}' cargado ({len(opciones)} opciones)")
            return opciones
    raise ValueError(
        f"Preset '{preset_name}' no encontrado.\n"
        f"     Disponibles: {', '.join(nombres)}"
    )


# ─────────────────────────────────────────────
# Gestión de proyectos
# ─────────────────────────────────────────────

def get_or_create_project(host: str, headers: dict, name: str, description: str) -> int:
    """Retorna el ID del proyecto, creándolo si no existe."""
    url = f"{host}/api/projects/"
    response = requests.get(url, headers=headers, timeout=30)
    response.raise_for_status()
    data = response.json()
    projects = data if isinstance(data, list) else data.get("results", [])
    for project in projects:
        if project["name"] == name:
            print(f"[OK] Proyecto existente: '{name}' (ID: {project['id']})")
            return project["id"]
    # Crear nuevo proyecto
    payload = {"name": name, "description": description}
    response = requests.post(url, headers=headers, json=payload, timeout=30)
    response.raise_for_status()
    project_id = response.json()["id"]
    print(f"[OK] Proyecto creado: '{name}' (ID: {project_id})")
    return project_id


# ─────────────────────────────────────────────
# Subida de imágenes
# ─────────────────────────────────────────────

def collect_images(images_dir: str) -> list[Path]:
    """Recolecta todas las imágenes JPG/JPEG/PNG del directorio."""
    dir_path = Path(images_dir)
    if not dir_path.exists():
        raise FileNotFoundError(f"Directorio de imágenes no encontrado: {images_dir}")
    extensions = {".jpg", ".jpeg", ".png", ".tif", ".tiff"}
    images = [p for p in dir_path.iterdir() if p.suffix.lower() in extensions]
    if not images:
        raise ValueError(f"No se encontraron imágenes en: {images_dir}")
    print(f"[OK] {len(images)} imágenes encontradas en '{images_dir}'")
    return sorted(images)


def create_task(
    host: str,
    headers: dict,
    project_id: int,
    task_name: str,
    images: list[Path],
    options: dict
) -> int:
    """
    Crea una tarea en WebODM subiendo las imágenes.
    WebODM acepta multipart/form-data con múltiples archivos 'images'.
    """
    url = f"{host}/api/projects/{project_id}/tasks/"

    # Convertir opciones dict a lista de {name, value} — WebODM exige strings
    options_list = [{"name": k, "value": str(v).lower() if isinstance(v, bool) else str(v)} for k, v in options.items()]

    print(f"[>>] Subiendo {len(images)} imágenes a WebODM...")
    files = []
    try:
        for img_path in tqdm(images, desc="Subiendo imágenes", unit="img"):
            files.append(("images", (img_path.name, open(img_path, "rb"), "image/jpeg")))

        data = {
            "name": task_name,
            "options": json.dumps(options_list)
        }
        response = requests.post(url, headers=headers, files=files, data=data, timeout=300)
        if not response.ok:
            print(f"[ERROR] Respuesta WebODM ({response.status_code}): {response.text}")
        response.raise_for_status()
    finally:
        for _, (_, file_obj, _) in files:
            file_obj.close()

    task_id = response.json()["id"]
    print(f"[OK] Tarea creada (ID: {task_id})")
    return task_id


# ─────────────────────────────────────────────
# Polling del estado
# ─────────────────────────────────────────────

STATUS_LABELS = {
    10: "Encolada",
    20: "Ejecutando",
    30: "Fallida",
    40: "Completada",
    50: "Cancelada",
}


def poll_task(
    host: str,
    headers: dict,
    project_id: int,
    task_id: int,
    interval: int = 30,
    timeout_minutes: int = 180
) -> dict:
    """Espera a que la tarea finalice, mostrando progreso."""
    url = f"{host}/api/projects/{project_id}/tasks/{task_id}/"
    max_checks = (timeout_minutes * 60) // interval
    print(f"\n[>>] Monitoreando tarea (polling cada {interval}s, timeout {timeout_minutes} min)...")

    for i in range(max_checks):
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        task = response.json()
        status = task["status"]
        progress = task.get("running_progress", 0.0) * 100
        label = STATUS_LABELS.get(status, f"Estado {status}")
        print(f"  [{i+1:>3}] {label} — {progress:.1f}%", end="\r")

        if status == 40:
            print(f"\n[OK] Tarea completada.")
            return task
        elif status in (30, 50):
            last_error = task.get("last_error", "Sin detalle")
            raise RuntimeError(f"Tarea terminó con estado '{label}': {last_error}")

        time.sleep(interval)

    raise TimeoutError(f"Timeout: la tarea no completó en {timeout_minutes} minutos")


# ─────────────────────────────────────────────
# Descarga de entregables
# ─────────────────────────────────────────────

ASSET_MAP = {
    "orthophoto_tif":  ("orthophoto.tif",      "odm_orthophoto.tif"),
    "point_cloud_las": ("georeferenced_model.laz", "nube_de_puntos.laz"),
    "model_3d_obj":    ("textured_model.zip",   "modelo_3d.zip"),
    "report_pdf":      ("report.pdf",           "reporte.pdf"),
}


def download_asset(
    host: str,
    headers: dict,
    project_id: int,
    task_id: int,
    asset_key: str,
    output_dir: Path
):
    """Descarga un asset específico de la tarea."""
    remote_name, local_name = ASSET_MAP[asset_key]
    url = f"{host}/api/projects/{project_id}/tasks/{task_id}/download/{remote_name}"
    output_path = output_dir / local_name

    response = requests.get(url, headers=headers, stream=True, timeout=120)
    if response.status_code == 404:
        print(f"  [!] Asset no disponible: {remote_name}")
        return
    response.raise_for_status()

    total = int(response.headers.get("content-length", 0))
    with open(output_path, "wb") as f, tqdm(
        desc=f"  {local_name}",
        total=total,
        unit="B",
        unit_scale=True
    ) as bar:
        for chunk in response.iter_content(chunk_size=8192):
            f.write(chunk)
            bar.update(len(chunk))
    print(f"  [OK] Guardado: {output_path}")


def download_all(
    host: str,
    headers: dict,
    project_id: int,
    task_id: int,
    exports: dict,
    output_dir: str
):
    """Descarga todos los assets habilitados en la config."""
    out_path = Path(output_dir)
    out_path.mkdir(parents=True, exist_ok=True)
    print(f"\n[>>] Descargando entregables en '{out_path}'...")
    for asset_key, enabled in exports.items():
        if enabled and asset_key in ASSET_MAP:
            download_asset(host, headers, project_id, task_id, asset_key, out_path)
    print("[OK] Descarga completada.")


# ─────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(
        description="Pipeline fotogramétrico WebODM — IPRE IPI-26-704"
    )
    parser.add_argument("--config",    required=True,       help="Ruta al archivo config.json")
    parser.add_argument("--images",    default=None,        help="Sobreescribe images_dir del config")
    parser.add_argument("--preset",    default=None,        metavar="NOMBRE", help="Nombre del preset WebODM a usar (ej: 'Fast Orthophoto'). Reemplaza las options del config. Usar --list-presets para ver disponibles")
    parser.add_argument("--list-presets", action="store_true", help="Lista los presets disponibles en WebODM y termina")
    parser.add_argument("--dry-run",   action="store_true", help="Valida config sin enviar a WebODM")
    parser.add_argument("--no-wait",   action="store_true", help="Sube las fotos y arranca la tarea, pero NO espera ni descarga. Útil para cerrar el PC y dejar procesando en el servidor")
    parser.add_argument("--download",  default=None,        metavar="TASK_ID", help="Solo descarga resultados de una tarea ya completada (requiere --project-id)")
    parser.add_argument("--project-id",default=None, type=int, metavar="ID",  help="ID del proyecto WebODM (usar con --download)")
    return parser.parse_args()


def main():
    args = parse_args()

    # 1. Leer config
    print(f"[>>] Leyendo configuración: {args.config}")
    config = load_config(args.config)

    # Permitir override de images_dir por CLI
    if args.images:
        config["task"]["images_dir"] = args.images

    if args.dry_run:
        print("[OK] Dry-run: configuración válida. No se envió nada a WebODM.")
        print(json.dumps(config, indent=2, ensure_ascii=False))
        sys.exit(0)

    # 2. Autenticar
    token = get_token(
        config["webodm"]["host"],
        config["webodm"]["username"],
        config["webodm"]["password"]
    )
    headers = auth_headers(token)
    host = config["webodm"]["host"]

    # Modo listar presets: muestra disponibles y termina
    if args.list_presets:
        presets = list_presets(host, headers)
        print("\nPresets disponibles en WebODM:")
        for p in presets:
            print(f"  - {p['name']}")
        sys.exit(0)

    # Aplicar preset si se especificó (reemplaza options del config)
    if args.preset:
        config["options"] = get_preset_options(host, headers, args.preset)

    # Modo solo-descarga: no sube nada, descarga tarea ya existente
    if args.download:
        if not args.project_id:
            print("[ERROR] --download requiere --project-id")
            sys.exit(1)
        task_id    = int(args.download)
        project_id = args.project_id
        print(f"[>>] Modo descarga: proyecto {project_id}, tarea {task_id}")
        poll_task(host, headers, project_id, task_id,
                  interval=config["polling"]["interval_seconds"],
                  timeout_minutes=config["polling"]["timeout_minutes"])
        download_all(host, headers, project_id, task_id,
                     config["exports"], config["task"]["output_dir"])
        print("\n[LISTO] Descarga completada.")
        sys.exit(0)

    # 3. Proyecto
    project_id = get_or_create_project(
        host, headers,
        config["project"]["name"],
        config["project"].get("description", "")
    )

    # 4. Imágenes
    images = collect_images(config["task"]["images_dir"])

    # 5. Crear tarea
    task_id = create_task(
        host, headers, project_id,
        config["task"]["name"],
        images,
        config["options"]
    )

    # Modo sin-espera: sube las fotos, arranca la tarea y termina
    if args.no_wait:
        print(f"\n[OK] Tarea enviada al servidor. Puedes cerrar tu PC.")
        print(f"     Monitorea el progreso en: {host}")
        print(f"     Para descargar los resultados cuando termine, ejecuta:")
        print(f"     python webodm_pipeline.py --config {args.config} --download {task_id} --project-id {project_id}")
        sys.exit(0)

    # 6. Polling
    poll_task(
        host, headers, project_id, task_id,
        interval=config["polling"]["interval_seconds"],
        timeout_minutes=config["polling"]["timeout_minutes"]
    )

    # 7. Descargar entregables
    download_all(
        host, headers, project_id, task_id,
        config["exports"],
        config["task"]["output_dir"]
    )

    print("\n[LISTO] Pipeline completado.")
    print(f"  Ortofoto:      {config['task']['output_dir']}/odm_orthophoto.tif")
    print(f"  Nube puntos:   {config['task']['output_dir']}/nube_de_puntos.laz")
    print(f"  Modelo 3D:     {config['task']['output_dir']}/modelo_3d.zip")
    print(f"  Reporte:       {config['task']['output_dir']}/reporte.pdf")


if __name__ == "__main__":
    main()
