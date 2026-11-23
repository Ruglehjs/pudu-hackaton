# Reemplazo de Música y Efectos de Sonido (Drop-In)

El sistema de audio de **Pudú Fantasy** (`audio.lua`) está diseñado para reemplazar cualquier canción o efecto de sonido más adelante **sin modificar código Lua**, funcionando tanto al correr desde carpeta como desde el `.exe` empaquetado.

## 1. Reemplazo rápido por carpeta (`assets/custom/audio/`)

Coloca tus archivos de audio en `assets/custom/audio/` con el **ID de la pista o SFX** (o el nombre base del archivo original). Se aceptan automáticamente **`.ogg`, `.wav`, `.mp3` y `.flac`** (en ese orden de prioridad).

Ejemplos:
- `assets/custom/audio/battle_gaviota.ogg` reemplaza la música de la **Gaviota Mafiosa**.
- `assets/custom/audio/overworld_chiloe.mp3` reemplaza la música de exploración de **Chiloé**.
- `assets/custom/audio/victory.ogg` reemplaza la fanfarria de **Victoria**.
- `assets/custom/audio/sfx_combo_electro.wav` reemplaza el SFX del combo eléctrico.

También puedes reemplazar directamente los archivos dentro de `assets/audio/` manteniendo el nombre base (por ejemplo, sustituir `assets/audio/bgm_battle_puma.wav` por `assets/audio/bgm_battle_puma.ogg`).

## 2. Recarga en caliente con `[F5]`

Con el juego abierto, presiona **`[F5]`** para recargar en vivo las pistas de música y efectos desde `assets/custom/audio/` o `assets/audio/` (actualizando también el BPM de `beat_sync.lua`).

## 3. Ajustar BPM, beats, offset o ruta (`tracks.json`)

Si reemplazas una canción por otra con distinto tempo, crea `assets/custom/audio/tracks.json` (o `assets/audio/tracks.json`) para mantener sincronizado el baile idle del Pudú en `beat_sync.lua`:

```json
{
  "battle_gaviota": {
    "path": "assets/custom/audio/mi_gaviota.ogg",
    "bpm": 128.0,
    "beats": 64,
    "beatOffset": 0.0,
    "loop": true
  },
  "overworld_desierto": {
    "bpm": 110.0,
    "beats": 64
  }
}
```

Todos los campos son opcionales; solo sobreescribe los que necesites.

## 4. IDs de pistas disponibles

| ID de pista | Uso | Archivo base |
|---|---|---|
| `overworld_desierto` | Exploración Atacama | `assets/audio/bgm_overworld_desierto.wav` |
| `overworld_costa` | Exploración Valparaíso | `assets/audio/bgm_overworld_costa.wav` |
| `overworld_bosque` | Exploración Cordillera de los Andes | `assets/audio/bgm_overworld_bosque.wav` |
| `overworld_chiloe` | Exploración Chiloé | `assets/audio/bgm_overworld_chiloe.wav` |
| `battle_fardo` | Batalla Fardo (Atacama) | `assets/audio/bgm_battle_pila_ropa.wav` |
| `battle_mancha` | Batalla La Mancha (Valparaíso) | `assets/audio/bgm_battle_gaviota.wav` |
| `battle_brasa` | Incendio forestal (jefe final de Chiloé) | `assets/audio/bgm_battle_puma.wav` |
| `battle_tempano` | Deshielo glaciar (Cordillera de los Andes) | `assets/audio/bgm_battle_caleuche.wav` |
| `victory` | Fanfarria de victoria | `assets/audio/bgm_victory.wav` |
| `defeat` | Jingle de derrota | `assets/audio/bgm_defeat.wav` |
