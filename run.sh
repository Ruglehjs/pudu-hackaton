#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${PUDU_BATTLE_PORT:-}"
if [[ -z "$PORT" && -f "$DIR/.env" ]]; then
    PORT="$(sed -nE 's/^[[:space:]]*PUDU_BATTLE_PORT[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$DIR/.env" | head -n 1)"
fi
PORT="${PORT:-18425}"
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( 10#$PORT < 1 || 10#$PORT > 65535 )); then
    echo "PUDU_BATTLE_PORT debe ser un puerto entre 1 y 65535." >&2
    exit 1
fi

LOVE_BIN=""
if [[ -x "$DIR/tools/love.app/Contents/MacOS/love" ]]; then
    LOVE_BIN="$DIR/tools/love.app/Contents/MacOS/love"
elif [[ -x "/Applications/love.app/Contents/MacOS/love" ]]; then
    LOVE_BIN="/Applications/love.app/Contents/MacOS/love"
elif command -v love >/dev/null 2>&1; then
    LOVE_BIN="$(command -v love)"
else
    echo "Error: LÖVE2D 11.5 no encontrado." >&2
    echo "Instálalo en $DIR/tools/love.app, /Applications/love.app o en tu PATH (comando 'love')." >&2
    exit 1
fi

bridge_healthy() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 0.5 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${PORT}/health', timeout=0.5)" >/dev/null 2>&1
    else
        return 1
    fi
}

BRIDGE_PID=""
cleanup() {
    if [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
        kill "$BRIDGE_PID" 2>/dev/null || true
    fi
}

MOCK=false
for flag in "$@"; do
    if [[ "$flag" == "--mock" ]]; then MOCK=true; fi
done
if [[ "$MOCK" == false && -f "$DIR/ai_bridge.py" ]] && command -v python3 >/dev/null 2>&1 && ! bridge_healthy; then
    PUDU_BATTLE_PORT="$PORT" python3 "$DIR/ai_bridge.py" >/dev/null 2>&1 &
    BRIDGE_PID=$!
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    for _ in {1..15}; do
        if bridge_healthy || ! kill -0 "$BRIDGE_PID" 2>/dev/null; then break; fi
        sleep 0.1
    done
fi

set +e
PUDU_BATTLE_PORT="$PORT" "$LOVE_BIN" "$DIR" ${1+"$@"}
STATUS=$?
set -e

exit "$STATUS"
