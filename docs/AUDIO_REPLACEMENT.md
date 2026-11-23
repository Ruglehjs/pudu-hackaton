# Sistema de Audio Dinámico y Reemplazo Drop-In (Google Lyria 3 + SFX HD-2D)

El sistema de audio de **Pudú Fantasy** (`audio.lua`) combina música instrumental generada con **Google Lyria 3** (`tools/generate_lyria_music.py`, `.ogg` estéreo de alta fidelidad con loops continuos), efectos de sonido HD-2D estilo Pokémon (`tools/generate_pokemon_sfx.py`, `44.1 kHz` estéreo) y transiciones dinámicas:

- **Crossfade equal-power (`1.35s`)** entre los 4 biomas al explorar Chile de norte a sur.
- **Tensión dinámica por cercanía a un jefe:** al acercarse el Pudú a un jefe sin derrotar, la música aumenta suavemente presencia (`+18%`) y acelera el beat (`+6.5%`), manteniéndose sincronizada con `beat_sync.lua`.
- **Presentación clara de combate y `VS`:** ducking rápido del mapa -> stinger de encuentro -> cortinilla -> riser + choque `VS` -> entrada a la arena -> música de batalla Pokémon.
- **Reemplazo 100% drop-in sin tocar código Lua**, compatible con carpeta local y `.exe` empaquetado.

## 1. Reemplazo rápido (`assets/custom/audio/`)

Coloca tus archivos de audio en `assets/custom/audio/` con el **ID de la pista o SFX** (o el nombre base del archivo original). Se aceptan **`.ogg`, `.wav`, `.mp3` y `.flac`** en ese orden de prioridad.

Ejemplos:
- `assets/custom/audio/overworld_montana.ogg` reemplaza la música de la **Cordillera de los Andes**.
- `assets/custom/audio/battle_brasa.mp3` reemplaza la música del jefe final **Incendio forestal (Brasa)**.
- `assets/custom/audio/sfx_versus_impact.wav` reemplaza el choque de la pantalla **VS**.

Presiona **`[F5]`** dentro del juego para recargar en caliente música, efectos y metadata `tracks.json`.

## 2. Ajustar BPM, beats, offset o ruta (`tracks.json`)

Crea o edita `assets/custom/audio/tracks.json` (o `assets/audio/tracks.json`, generado automáticamente por `tools/generate_lyria_music.py`):

```json
{
  "battle_tempano": {
    "path": "assets/custom/audio/mi_tempano.ogg",
    "bpm": 144.0,
    "beats": 68,
    "beatOffset": 0.0,
    "loop": true
  }
}
```

## 3. IDs de pistas principales

| ID de pista | Uso | Archivo base |
|---|---|---|
| `overworld_desierto` | Exploración Desierto de Atacama | `assets/audio/bgm_overworld_desierto.ogg` |
| `overworld_costa` | Exploración Costa y Muelle de Valparaíso | `assets/audio/bgm_overworld_costa.ogg` |
| `overworld_montana` | Exploración Cordillera de los Andes | `assets/audio/bgm_overworld_montana.ogg` |
| `overworld_chiloe` | Exploración Bosque de Chiloé | `assets/audio/bgm_overworld_chiloe.ogg` |
| `battle_fardo` | Batalla Vertedero de telas / Fardo (Atacama) | `assets/audio/bgm_battle_fardo.ogg` |
| `battle_mancha` | Batalla Derrame de petróleo / La Mancha (Valparaíso) | `assets/audio/bgm_battle_mancha.ogg` |
| `battle_tempano` | Batalla Deshielo glaciar / Témpano (Cordillera) | `assets/audio/bgm_battle_tempano.ogg` |
| `battle_brasa` | Batalla Incendio forestal / Brasa (Jefe Final — Chiloé) | `assets/audio/bgm_battle_brasa.ogg` |
| `victory` | Fanfarria de victoria | `assets/audio/bgm_victory.ogg` |
| `defeat` | Jingle de derrota | `assets/audio/bgm_defeat.ogg` |

## 4. Regenerar música con Google Lyria 3 o SFX

```powershell
# Regenerar pistas o solo una pista específica con Google Lyria 3 (requiere GEMINI_API_KEY en .env)
python tools/generate_lyria_music.py --force --only battle_brasa

# Regenerar los SFX HD-2D estilo Pokémon (preserva los 4 jingles de Lyria por defecto)
python tools/generate_pokemon_sfx.py
```
