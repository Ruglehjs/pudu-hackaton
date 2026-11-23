"""Empaqueta el juego offline con el runtime oficial de LÖVE 11.5 Win64."""

from pathlib import Path
from shutil import copyfileobj, copy2
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
LUA_FILES = (
    "conf.lua", "main.lua", "json.lua", "encounters.lua", "stage_renderer.lua",
    "asset_loader.lua", "audio.lua", "battle_judge.lua", "battle_worker.lua",
    "sprite_worker.lua", "worker_http.lua",
)
DLL_FILES = ("SDL2.dll", "love.dll", "lua51.dll", "OpenAL32.dll",
             "mpg123.dll", "msvcp120.dll", "msvcr120.dll")


def build():
    runtime = ROOT / "tools/love-win64"
    dist = ROOT / "dist"
    target = dist / "PuduFantasy-Windows"
    target.mkdir(parents=True, exist_ok=True)
    love = dist / "PuduFantasy.love"
    with ZipFile(love, "w", ZIP_DEFLATED) as archive:
        for name in (*LUA_FILES, "battle_rules.json"):
            archive.write(ROOT / name, name)
        for asset in sorted((ROOT / "assets").rglob("*")):
            if asset.is_file() and asset.name != ".gitkeep":
                archive.write(asset, asset.relative_to(ROOT))

    exe = target / "PuduFantasy.exe"
    with exe.open("wb") as output:
        for part in (runtime / "love.exe", love):
            with part.open("rb") as source:
                copyfileobj(source, output)
    with ZipFile(dist / "PuduFantasy-Windows-x64.zip", "w", ZIP_DEFLATED) as package:
        package.write(exe, exe.name)
        for name in (*DLL_FILES, "license.txt"):
            copy2(runtime / name, target / name)
            package.write(target / name, name)
        for folder in ("assets/custom", "screenshots"):
            (target / folder).mkdir(parents=True, exist_ok=True)
            package.writestr(folder + "/", "")
    print(exe)


if __name__ == "__main__":
    build()
