"""Play four turns through LÖVE input events. Run: python tests/smoke_game.py."""

import argparse
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import zipfile


ROOT = Path(__file__).resolve().parents[1]
HARNESS = """
require("game_main")
local updateGame = love.update
local ordinaryPrint = print
local game
for i = 1, 40 do
    local name, value = debug.getupvalue(updateGame, i)
    if name == "Game" then game = value; break end
end
assert(game)
local turns, step = 0, 1
local arrows, nextArrow, arrowTimer = {"up", "left", "down", "right"}, 1, 0
function print(line, ...)
    ordinaryPrint(line, ...)
    if type(line) == "string" and line:match("^%[BATALLA%]") then turns = turns + 1 end
end
local function key(name)
    love.event.push("keypressed", name, name, false)
    love.event.push("keyreleased", name, name)
end
local function cast(text)
    love.event.push("textinput", text)
    key("return")
end
function love.update(dt)
    updateGame(dt)
    local onMap = game.mode == "explore" and game.transitionState == "none"
    local playerReady = game.battlePhase == "player_turn" and game.hud.promptOpen
    if (step == 3 and turns == 1) or (step == 4 and turns == 2) or (step == 7 and turns == 3) then
        arrowTimer = arrowTimer + dt
        if arrowTimer >= 0.09 then
            key(arrows[nextArrow])
            nextArrow = nextArrow % #arrows + 1
            arrowTimer = 0
        end
    end
    if step == 1 and playerReady then
        love.event.push("textinput", "modo diosá")
        key("backspace")
        key("return")
    elseif step == 2 and turns == 1 and playerReady then
        cast("charco")
    elseif step == 3 and turns == 2 then
        local signal = io.open(os.getenv("PUDU_SMOKE_DISCONNECTED"), "rb")
        if not signal then return end
        signal:close()
        cast("rayo")
    elseif step == 4 and turns == 3 then
        key("return")
    elseif step == 5 and onMap then
        key("tab")
    elseif step == 6 and playerReady then
        cast("rayo")
    elseif step == 7 and turns == 4 then
        key("escape")
    elseif step == 8 and onMap then
        key("escape")
    else
        return
    end
    step = step + 1
end
"""
TURN = re.compile(r"turno=(\d+) rival=(\S+) juez=(\S+) ms=(\d+) aprobado=(\w+) "
                  r"resultado=(\S+) estado=(\S+) combo=(\S+)")


def launch(args, env):
    process = subprocess.Popen(args, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               encoding="utf-8", errors="replace",
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    lines = queue.Queue()

    def read():
        with process.stdout:
            for line in process.stdout:
                lines.put(line.rstrip())
        lines.put(None)

    threading.Thread(target=read, daemon=True).start()
    return process, lines


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def prepare_game(path):
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("main.lua", HARNESS.encode("utf-8"))
        for lua in ROOT.glob("*.lua"):
            if lua.name == "conf.lua":
                conf = lua.read_text(encoding="utf-8").replace("pudu_fantasy_battle", "pudu_fantasy_smoke")
                archive.writestr("conf.lua", conf)
            else:
                archive.write(lua, "game_main.lua" if lua.name == "main.lua" else lua.name)
        archive.write(ROOT / "battle_rules.json", "battle_rules.json")
        for asset in (ROOT / "assets").rglob("*"):
            if asset.is_file() and asset.name != ".gitkeep":
                archive.write(asset, asset.relative_to(ROOT).as_posix())


def smoke(love):
    with tempfile.TemporaryDirectory(prefix="pudu-fase03-") as temp:
        path = Path(temp)
        game_file, signal = path / "partida.love", path / "offline"
        prepare_game(game_file)
        env = {**os.environ, "PYTHONIOENCODING": "utf-8", "PUDU_SMOKE_DISCONNECTED": str(signal)}
        bridge, bridge_lines = launch([sys.executable, str(ROOT / "ai_bridge.py"), "--mock", "--port", "0"], env)
        try:
            ready = bridge_lines.get(timeout=15)
            address = re.search(r"127\.0\.0\.1:(\d+) ", ready or "")
            if not address:
                raise RuntimeError(f"El puente de prueba no arrancó: {ready}")
            env["PUDU_BATTLE_PORT"] = address.group(1)
            game, lines = launch([str(love), str(game_file), "--mode=battle", "--encounter=7",
                                  "--quit-after=35"], env)
            try:
                turns, logs = [], []
                deadline = time.monotonic() + 45
                while True:
                    line = lines.get(timeout=max(0, deadline - time.monotonic()))
                    if line is None:
                        break
                    logs.append(line)
                    match = TURN.search(line)
                    if match:
                        turns.append(match.groups())
                        print(line, flush=True)
                        if len(turns) == 2:
                            stop(bridge)
                            signal.touch()
                if game.wait(timeout=3) != 0 or any("[PUDU FANTASY ERROR]" in s for s in logs):
                    raise RuntimeError("\n".join(logs))
            finally:
                stop(game)
        finally:
            stop(bridge)

    observed = [(turn, source, approved, state, combo) for turn, _, source, _, approved, _, state, combo in turns]
    expected = [
        ("1", "mock", "false", "none", "none"),
        ("1", "mock", "true", "mojado", "none"),
        ("2", "lua", "true", "none", "combo_electro"),
        ("1", "lua", "true", "none", "none"),
    ]
    if observed != expected or turns[2][1] != turns[1][1] or turns[3][1] == turns[2][1]:
        raise AssertionError(f"Secuencia inesperada: {turns}\n" + "\n".join(logs[-15:]))
    print("OK: retroceso UTF-8, rechazo sin gastar turno, combo tras desconectar el puente y arena reiniciada.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--love", help="Ruta al ejecutable LÖVE 11.5")
    args = parser.parse_args()
    bundled = ROOT / "tools" / "love-win64" / "lovec.exe"
    engine = args.love or (str(bundled) if bundled.exists() else shutil.which("love"))
    if not engine:
        parser.error("Indica la ruta de LÖVE 11.5 con --love.")
    smoke(engine)
