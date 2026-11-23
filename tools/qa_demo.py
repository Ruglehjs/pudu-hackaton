"""Genera las capturas, auditoría y pruebas reproducibles de la Fase 7."""

import argparse
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import ZipFile

from PIL import Image, ImageFont

from build_windows_exe import BRIDGE_FILES, ROOT, build, bundled_assets, verify_modules

sys.path.insert(0, str(ROOT))
from tests.phase07_fuzz import run_fuzz

DIST = ROOT / "dist"
OUTPUT = ROOT / "screenshots/qa_final"
ENGINE = ROOT / "tools/love-win64/lovec.exe"
PERF = re.compile(r"\[PERF\] fps=(\d+) deferred=(\w+) gi=(\w+) bloom=(\w+) drawcalls=(\d+)")
SCENES = (
    ("01_overworld_desierto", 2, "--mode=explore", "--biome=desierto"),
    ("02_overworld_costa", 2, "--mode=explore", "--biome=costa"),
    ("03_overworld_montana", 2, "--mode=explore", "--biome=montana"),
    ("04_overworld_chiloe", 2, "--mode=explore", "--biome=chiloe"),
    ("05_transicion_jrpg", 1.8, "--mode=explore", "--encounter=3", "--transition-preview=0.45"),
    ("06_batalla_inicio", 1.4, "--mode=battle", "--encounter=1", "--battle-enter-preview", "--screenshot-phase=battle_enter"),
    ("07_batalla_ritual_flechas", 2.2, "--mode=battle", "--encounter=1", "--test-ritual"),
    ("08_batalla_impacto_critico", 6.2, "--mode=battle", "--encounter=1", "--auto-prompt=lavadora", "--screenshot-phase=impact_hold"),
    ("09_combo_electro", 6.5, "--mode=battle", "--encounter=5", "--demo-combo=combo_electro", "--screenshot-phase=combo"),
    ("10_combo_hielo", 6.5, "--mode=battle", "--encounter=6", "--demo-combo=combo_deep_freeze", "--screenshot-phase=combo"),
    ("11_lighting_noche_hd2d", 2.2, "--mode=battle", "--encounter=4", "--lighting=noche"),
    ("12_lighting_atardecer", 2.2, "--mode=battle", "--encounter=2", "--lighting=atardecer"),
    ("13_panel_director", 2, "--mode=battle", "--encounter=1", "--open-director"),
)
EXTRA_SCENES = (
    ("05b_alerta_encuentro", 1.8, "--mode=explore", "--encounter=3", "--transition-preview=0.0"),
    ("08b_final_llanto_preview", 3, "--mode=battle", "--encounter=7", "--demo-finale=crying", "--screenshot-phase=victory"),
)
SMOKE_ARGS = ("--mode=battle", "--encounter=1", "--auto-prompt=lavadora", "--screenshot-phase=victory")


def audit_assets():
    loader = (ROOT / "asset_loader.lua").read_text(encoding="utf-8-sig")
    encounters = (ROOT / "encounters.lua").read_text(encoding="utf-8-sig")
    rules = json.loads((ROOT / "battle_rules.json").read_text(encoding="utf-8-sig"))
    audio = (ROOT / "audio.lua").read_text(encoding="utf-8-sig")
    gags = re.findall(r"^\s*(\w+)\s*=", loader.split("local gagTiles = {", 1)[1].split("}", 1)[0], re.M)
    sprite_names = set(rules["sprites"]) | set(gags) | {"pudu_wizard_hat"}
    pairs = {"assets/sprites/" + name for name in ("pudu_8dir_sheet", "pudu_hero")}
    pairs.update(re.findall(r'spritePath\s*=\s*"(assets/[^"]+)"', encounters))
    pairs.update(f"assets/sprites/{'gags/' if name in gags or name == 'pudu_wizard_hat' else ''}{name}"
                 for name in sprite_names)
    pairs.update(f"assets/tiles/{name}" for name in ("grass_floor", "stone_floor", "desert_floor", "mountain_floor", "coast_floor"))
    pngs = {stem + suffix for stem in pairs for suffix in (".png", "_n.png")}
    pngs.add("assets/sprites/light_radial.png")
    pngs.update(f"assets/ui/portraits/pudu_{mood}.png" for mood in ("happy", "shocked", "angry"))
    tracks = set(re.findall(r'"(assets/audio/[^\"]+\.(?:wav|ogg))"', audio))
    font = "assets/fonts/PTSans.ttc"
    package = {name for _, name in bundled_assets()}
    required = pngs | tracks | {font}
    missing = sorted(required - package)
    invalid = []
    dimensions = {}
    for name in sorted(pngs & package):
        try:
            with Image.open(ROOT / name) as png:
                if png.format != "PNG":
                    raise ValueError("formato distinto de PNG")
                dimensions[name] = png.size
                png.verify()
            if "/gags/" in name and not name.endswith("_n.png"):
                with Image.open(ROOT / name) as png:
                    rgba = png.convert("RGBA")
                    if rgba.getchannel("A").getextrema() != (0, 255):
                        raise ValueError("el gag requiere cobertura sólida y fondo transparente")
                    if any(r >= 250 and g < 15 and b >= 250 and a for r, g, b, a in rgba.getdata()):
                        raise ValueError("magenta visible en el gag")
        except (OSError, SyntaxError, ValueError) as error:
            invalid.append(f"{name}: {error}")
    for stem in sorted(pairs):
        diffuse, normal = dimensions.get(stem + ".png"), dimensions.get(stem + "_n.png")
        if diffuse and normal and diffuse != normal:
            invalid.append(f"{stem}: tamaño diffuse {diffuse} distinto de normal {normal}")
    hero = dimensions.get("assets/sprites/pudu_8dir_sheet.png")
    if hero and (hero[0] % 6 or hero[1] % 8):
        invalid.append("pudu_8dir_sheet: tamaño incompatible con la grilla 6×8")
    for name in sorted(tracks & package):
        with (ROOT / name).open("rb") as file:
            header = file.read(12)
        valid = header.startswith(b"OggS") if name.endswith(".ogg") else header.startswith(b"RIFF") and header[8:] == b"WAVE"
        if not valid:
            invalid.append(f"{name}: cabecera de audio inválida")
    if font in package:
        try:
            ImageFont.truetype(str(ROOT / font), 14)
        except OSError as error:
            invalid.append(f"{font}: {error}")
    return {"requeridos": len(required), "presentes": len(required & package), "pares_presentes": sum(
        stem + ".png" in dimensions and stem + "_n.png" in dimensions for stem in pairs),
        "faltantes": missing, "invalidos": invalid}


def closed_port():
    # Hold a loopback port without listening, so a running bridge cannot answer.
    reserved = socket.socket()
    reserved.bind(("127.0.0.1", 0))
    return reserved


def capture(command, env, scene, *, standalone=False):
    name, timeout, *flags = scene
    output = OUTPUT / (name + ".png")
    output.unlink(missing_ok=True)
    if not standalone:
        flags.append("--mock")
    flags.append("--qa-no-save")
    args = [*flags, "--print-perf", f"--quit-after={timeout}", f"--screenshot={output.as_posix()}"]
    run = subprocess.run([*command, *args], cwd=ROOT, env=env, capture_output=True,
                         encoding="utf-8", errors="replace", timeout=timeout + 25)
    stdout, stderr = run.stdout.strip(), run.stderr.strip()
    errors = []
    if run.returncode != 0 or stderr or "[PUDU FANTASY ERROR]" in stdout:
        errors.append(f"Salida {run.returncode}: {stderr or stdout}")
    try:
        with Image.open(output) as png:
            if png.format != "PNG" or png.size != (1280, 720):
                errors.append(f"Captura inesperada: {png.format} {png.size}")
            png.verify()
    except (OSError, SyntaxError) as error:
        errors.append(f"Captura no verificable: {error}")
    perf = PERF.search(stdout)
    if standalone and not re.search(r"rival=pila_de_ropa juez=lua .*aprobado=true .*resultado=super_funny_ko", stdout):
        errors.append("Falta la confirmación de victoria con el juez Lua en el log")
    if not perf:
        errors.append("Falta la medición [PERF]")
    metrics = dict(zip(("fps", "deferred", "gi", "bloom", "drawcalls"), perf.groups())) if perf else None
    report = {"archivo": output.name, "args": args[:-1], "salida": run.returncode, "perf": metrics,
              "stdout": stdout, "stderr": stderr, "errores": errors}
    print(f"{name}: {'FAIL' if errors else 'OK'}" + (f" ({metrics['fps']} FPS)" if metrics else ""), flush=True)
    return report


def build_sizes():
    files = ("PuduFantasy.love", "PuduFantasy-Windows/PuduFantasy.exe", "PuduFantasy-Windows-x64.zip")
    return {name: (DIST / name).stat().st_size for name in files}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--love", type=Path, default=ENGINE, help="Binario de consola LÖVE 11.5")
    parser.add_argument("--live", action="store_true", help="Enviar tres prompts de prueba a Gemini si está configurado")
    args = parser.parse_args()
    engine = args.love.resolve()
    verify_modules()
    for path in (*sorted(ROOT.glob("*.py")), *sorted((ROOT / "tools").glob("*.py")), ROOT / "tests/phase07_fuzz.py"):
        compile(path.read_bytes(), str(path), "exec")
    build()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report = {"assets": audit_assets(), "build_bytes": build_sizes(), "capturas": {}}
    env = os.environ.copy()
    for scene in (*SCENES, *EXTRA_SCENES):
        name = scene[0]
        report["capturas"][name] = capture([engine, ROOT], env, scene)
    if not (ROOT / "director_panel.lua").is_file():
        report["capturas"]["13_panel_director"]["errores"].append("Esta revisión no implementa el Panel Director")
    with closed_port() as reserved:
        env["PUDU_BATTLE_PORT"] = str(reserved.getsockname()[1])
        scene = ("15_standalone_offline_smoke", 6.5, *SMOKE_ARGS)
        report["capturas"][scene[0]] = capture([engine, DIST / "PuduFantasy.love"], env, scene, standalone=True)
        with tempfile.TemporaryDirectory(prefix="pudu-win64-") as folder:
            with ZipFile(DIST / "PuduFantasy-Windows-x64.zip") as package:
                package.extractall(folder)
            scene = ("15b_exe_extraido_offline", 6.5, *SMOKE_ARGS)
            exe = Path(folder) / "PuduFantasy.exe"
            report["capturas"][scene[0]] = capture([exe], env, scene, standalone=True)
    report["fuzz"] = run_fuzz(engine, live=args.live)
    (OUTPUT / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Evidencia: {OUTPUT / 'manifest.json'}")
    has_fuzz_error = any(case["errores"] for mode in ("lua", "http_mock") for case in report["fuzz"][mode].values())
    has_capture_error = any(scene["errores"] for scene in report["capturas"].values())
    asset_fail = bool(report["assets"]["faltantes"] or report["assets"]["invalidos"])
    live = report["fuzz"]["http_live"]
    live_fail = args.live and (live["estado"] != "ejecutado" or any(case["errores"] for case in live["casos"].values()))
    return int(has_fuzz_error or has_capture_error or asset_fail or live_fail)


if __name__ == "__main__":
    raise SystemExit(main())
