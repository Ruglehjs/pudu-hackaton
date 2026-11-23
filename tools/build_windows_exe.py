"""Construye y verifica el paquete portable de LÖVE 11.5 Win64."""

import re
from pathlib import Path
from shutil import copyfileobj, copy2
from struct import unpack
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
LUA_FILES = (
    "conf.lua", "main.lua", "json.lua", "encounters.lua", "stage_renderer.lua",
    "desert_arrival.lua", "chile_coastline.lua", "adventure_screen.lua",
    "asset_loader.lua", "audio.lua", "battle_judge.lua", "battle_worker.lua",
    "sprite_worker.lua", "worker_http.lua", "beat_sync.lua", "shaders.lua",
    "spell_ritual.lua", "battle_hud.lua", "battle_ui_skin.lua", "battle_scores.lua",
    "battle_fx.lua", "battle_fx_spectacles.lua",
)
DLL_FILES = ("SDL2.dll", "love.dll", "lua51.dll", "OpenAL32.dll",
             "mpg123.dll", "msvcp120.dll", "msvcr120.dll")
BRIDGE_FILES = ("Jugar_con_IA.bat", "run_windows.ps1", "ai_bridge.py",
                "sprite_pipeline.py", "battle_rules.json", "requirements.txt", ".env.example")
PACKAGE_FOLDERS = ("assets/custom/", "screenshots/")
SKIP_AUDIO_PREFIXES = (
    "music_biome_", "music_crescendo_", "music_stem_", "music_cozy_theme",
    "ambient_", "battle_overworld_116", "battle_superstar_132", "battle_boss_144",
    "battle_plaza_120", "battle_victory_fanfare",
)
SKIP_ASSET_FOLDERS = ("assets/audio/lyria_raw/", "assets/custom/")
ENGINE_MODULES = {"utf8", "love.filesystem", "love.video", "socket", "socket.http", "ltn12"}
LOCAL_REQUIRE = re.compile(r"\brequire\s*\(?\s*['\"]([\w.]+)['\"]")


def verify_modules():
    for name in LUA_FILES:
        source = (ROOT / name).read_text(encoding="utf-8-sig")
        for module in LOCAL_REQUIRE.findall(source):
            if module not in ENGINE_MODULES and module.replace(".", "/") + ".lua" not in LUA_FILES:
                raise ValueError(f"{name} requiere {module}, ausente de LUA_FILES")


def bundled_assets():
    for asset in sorted((ROOT / "assets").rglob("*")):
        name = asset.relative_to(ROOT).as_posix()
        if not asset.is_file() or any(part.startswith(".") for part in asset.relative_to(ROOT / "assets").parts):
            continue
        if name.startswith(SKIP_ASSET_FOLDERS):
            continue
        if name.startswith("assets/audio/") and asset.name.startswith(SKIP_AUDIO_PREFIXES):
            continue
        yield asset, name


def verify_zip(archive, required):
    missing = set(required) - set(archive.namelist())
    if missing:
        raise ValueError(f"{archive.filename}: faltan {', '.join(sorted(missing))}")
    corrupt = archive.testzip()
    if corrupt is not None:
        raise ValueError(f"{archive.filename}: CRC incorrecto para {corrupt}")


def verify_win64(path):
    with path.open("rb") as file:
        if file.read(2) != b"MZ":
            raise ValueError(f"{path.name}: falta la firma MZ")
        file.seek(0x3C)
        file.seek(unpack("<I", file.read(4))[0])
        if file.read(6) != b"PE\0\0\x64\x86":
            raise ValueError(f"{path.name}: se esperaba un PE x86-64")


def build():
    runtime = ROOT / "tools/love-win64"
    dist = ROOT / "dist"
    target = dist / "PuduFantasy-Windows"
    verify_modules()
    for name in ("love.exe", *DLL_FILES):
        verify_win64(runtime / name)
    assets = list(bundled_assets())
    game_files = (*LUA_FILES, "battle_rules.json", *(name for _, name in assets))
    external_files = (*DLL_FILES, "license.txt", "LEEME_WINDOWS.txt", *BRIDGE_FILES)
    target.mkdir(parents=True, exist_ok=True)
    love = dist / "PuduFantasy.love"
    with ZipFile(love, "w", ZIP_DEFLATED) as archive:
        for name in (*LUA_FILES, "battle_rules.json"):
            archive.write(ROOT / name, name)
        for asset, name in assets:
            compression = ZIP_STORED if asset.suffix in (".ogg", ".ogv") else ZIP_DEFLATED
            archive.write(asset, name, compress_type=compression)

    exe = target / "PuduFantasy.exe"
    with exe.open("wb") as output:
        for part in (runtime / "love.exe", love):
            with part.open("rb") as source:
                copyfileobj(source, output)
    release = dist / "PuduFantasy-Windows-x64.zip"
    for name in external_files:
        if name in (*DLL_FILES, "license.txt"):
            source = runtime / name
        elif name == "LEEME_WINDOWS.txt":
            source = ROOT / "tools" / name
        else:
            source = ROOT / name
        copy2(source, target / name)
    with ZipFile(release, "w", ZIP_DEFLATED) as package:
        package.write(exe, exe.name)
        for name in external_files:
            package.write(target / name, name)
        for folder in PACKAGE_FOLDERS:
            (target / folder).mkdir(parents=True, exist_ok=True)
            package.writestr(folder, "")

    verify_win64(exe)
    with ZipFile(love) as archive, ZipFile(exe) as fused, ZipFile(release) as package:
        verify_zip(archive, game_files)
        verify_zip(fused, game_files)
        verify_zip(package, (exe.name, *external_files, *PACKAGE_FOLDERS))
    for path in (love, exe, release):
        print(f"{path.relative_to(ROOT)}: {path.stat().st_size:,} bytes")


if __name__ == "__main__":
    build()
