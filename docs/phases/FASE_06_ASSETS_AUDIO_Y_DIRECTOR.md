# FASE 06 — Arte HD-2D (`_n.png`), Música y SFX, Hot-Reload `[F5]` y Panel Director `[F2]`

| Campo | Detalle |
| :--- | :--- |
| **Fase** | **06 de 07** — Pipeline de Assets (Propios + IA), Audio Sincronizado al Compás y Herramientas de Producción en Vivo |
| **Duración estimada en hackathon** | **3 – 4 horas** (en paralelo: 3 subagentes de Codex construyen Audio, Pipeline de Arte/Normales y Panel Director `[F2]`, mientras el artista/músico del equipo deja caer sus archivos reales y los ve brillar en vivo con `[F5]`) |
| **Prerrequisitos (Gate de entrada)** | Fase 05 superada: `battle_fx.lua`, `victory_album.lua`, `beat_sync.lua`, `stage_renderer.lua` y `lighting_pipeline.lua` operativos en `main.lua`, con soporte de parejas `{ diff, norm }` (`*_n.png`) en los shaders HD-2D y soporte de `stage_overrides.json` en `encounters.lua`. |
| **Entregables concretos** | 1. **Pipeline de Arte HD-2D**: estructura canónica de carpetas (`assets/sprites/`, `encounters/`, `gags/`, `tiles/`, `ui/portraits/`, `assets/custom/`), generador automático en lote de mapas normales `_n.png` para sprites del artista (`tools/batch_normals.py` / `sprite_studio.py`), generadores IA opcionales en lote para sprites faltantes (`tools/generate_encounter_sprites.py`, `tools/generate_popular_gags.py`) y **Live Hot-Reload `[F5]`** sin reiniciar.<br>2. **Sistema de Audio & Ritmo (`audio.lua`)**: soporte para **canción propia del equipo** con `BPM` y `beatOffset` exactos (`user_battle`), pipeline opcional de pistas instrumentales con Vertex AI `global/lyria-3-pro-preview` (`tools/generate_lyria3_music.py`) + sintetizador procedural sin dependencias externas de **5 pistas fallback y 19 SFX cómicos/rituales** (`tools/generate_battle_music.py`).<br>3. **Panel Director (`director_panel.lua`, tecla `[F2]`)**: consola flotante de 3 pestañas (`1. ENCUENTROS`, `2. REACCIONES`, `3. GRÁFICA`) con 9 encuentros, 4 biomas, 14 reacciones forzadas, 4 botones de Super-Combos en 1 clic, iluminación/clima/cámara/escalas/offsets, guías de anclaje, ocultar HUD `[H]`, guardado en `stage_overrides.json` y capturas limpias `[F12]`. |

---

## 1. Objetivo de Producción y Alcance (Qué SÍ y Qué NO hacer en esta fase)

En una hackathon, la diferencia entre un prototipo bonito y un juego ganador se define en **qué tan rápido puede iterar el equipo de arte, música y diseño sin esperar recompilaciones ni depender del programador**. Esta fase construye la **fábrica de assets + cabina de dirección en vivo** de Pudú Fantasy.

### Qué SÍ hacer en esta fase
- **Integrar sprites 2D del artista del equipo al instante con iluminación HD-2D real**:
  - Definir la estructura exacta de carpetas y la carpeta de pruebas rápidas `assets/custom/<id>.png` (prioridad sobre el sprite por defecto).
  - Automatizar la generación en lote de mapas normales en espacio tangente (`*_n.png`) mediante filtro Sobel + domo gaussiano de alfa (`generate_normal_map`), para que cualquier dibujo 2D de Aseprite/Photoshop reciba luces direccionales, sombras suaves y Radiance Cascades al instante.
  - Implementar **Hot-Reload en vivo `[F5]`** leyendo bytes directamente desde disco (`io.open` → `love.filesystem.newFileData` → `love.graphics.newImage`), funcionando tanto en desarrollo (`love .`) como en builds empacados (`.exe` fused).
- **Cubrir huecos de arte con generación IA en lote (opcional y selectiva)**:
  - `tools/generate_encounter_sprites.py` (8 rivales + 4 gags icónicos) y `tools/generate_popular_gags.py` (10 gags populares de playtesters) usando Vertex AI `global/gemini-2.5-flash-image` anclado a `assets/sprites/pudu_hero.png`, con limpieza chroma `#FF00FF`, flood-fill desde esquinas, despill de halo magenta, trim/pad, mapa normal `_n.png` y QA programático (`< 2%` magenta residual, esquinas 100% transparentes).
- **Construir el motor musical sincronizado al compás y la biblioteca de 19 SFX (`audio.lua`)**:
  - Cargar música como `"static"` en LÖVE2D para lectura con precisión de muestra (`source:tell("seconds")`) sin drift, exponiendo `{ trackId, bpm, beatOffset, pos, duration, playing }` a `beat_sync.lua` para que el Pudú baile exactamente al pulso de la canción del equipo.
  - **Camino 1 (Música propia del equipo)**: cómo colocar `assets/audio/battle_user_main.wav` (o `.ogg`), medir su `bpm` y `beatOffset` exactos con DSP, y registrarla en `Audio.TRACK_META.user_battle`.
  - **Camino 2 (Vertex AI Lyria 3 Pro)**: `tools/generate_lyria3_music.py` (`global/lyria-3-pro-preview`) para generar hasta 5 pistas instrumentales (`superstar`, `boss`, `plaza`, `overworld`, `victory`), analizar BPM/downbeat, cortar múltiplos exactos de 4 compases con crossfade equal-power de `25 ms` (cero clicks), normalizar a `-1.5 dBFS` y exportar `.ogg`.
  - **Camino 3 (100% offline / 19 SFX cómicos y de ritual)**: `tools/generate_battle_music.py` (solo Python + NumPy, 44100 Hz 16-bit PCM) generando los **10 SFX cómicos** (`sfx_cry_wah`, `sfx_splat`, `sfx_boing`, `sfx_laugh`, `sfx_camera_flash`, `sfx_horn`, `sfx_rimshot`, `sfx_rain_pour`, `sfx_meow_scared`, `sfx_seagull`) + **9 SFX de ritual/encuentro** (`sfx_spell_arrow_1..6` pentatónica C5→C6 con shimmer automático a C7 en `playArrowChime()`, `sfx_spell_miss`, `sfx_spell_unleash`, `sfx_encounter_start`), además de 5 pistas procedurales de respaldo.
- **Construir el Panel Director `[F2]` (`director_panel.lua`)**:
  - 3 pestañas (`1. ENCUENTROS`, `2. REACCIONES`, `3. GRÁFICA`) para saltar a los 9 encuentros (con filtro por categoría), teletransportarse a los 4 biomas, cambiar pista musical, forzar las 14 reacciones del rival y 4 poses del Pudú, disparar **4 Super-Combos en 1 clic** + prueba de flechas, cambiar escenarios/iluminación/clima, ajustar zoom/escalas/offsets en vivo, activar guías de anclaje, ocultar el HUD (`[H]`), recargar PNGs (`[F5]`), guardar calibración permanente en `stage_overrides.json` y sacar capturas limpias (`[F12]`).

### Qué NO hacer en esta fase
- **NO** sobrescribir arte o música hechos a mano por el equipo al correr scripts de IA: todos los generadores deben saltar archivos existentes salvo que se pase `--force` explícito (y soportar `--only <id>`).
- **NO** cargar pistas de música con modo `"stream"` en LÖVE2D si se usan para `beat_sync.lua` (usar `"static"` garantiza `source:tell("seconds")` estable y loop exacto).
- **NO** meter el Panel Director en la experiencia normal del jugador: arranca cerrado (`open = false`) y solo aparece con `[F2]` (o botón discreto para demo/artistas).
- **NO** empacar instaladores finales ni preparar el guion de pitch aquí (eso es la **Fase 07**).

---

## 2. Modo Assets: ¿Ya tengo sprites/música o los incorporo después?

Esta es la **guía maestra de incorporación de assets** para que artistas, músicos y programadores trabajen en paralelo sin bloquearse.

### 2.1 Estructura Canónica de Carpetas de Arte

```text
assets/
├── sprites/
│   ├── pudu_8dir_sheet.png          + pudu_8dir_sheet_n.png    (spritesheet 6×8, 8 direcciones)
│   ├── pudu_hero.png                + pudu_hero_n.png          (referencia oficial de estilo 16-bit)
│   ├── light_radial.png                                        (gradiente radial para luz suave)
│   ├── <prop>.png                   + <prop>_n.png             (árboles, faroles, flora, fauna)
│   ├── encounters/                                             (8 rivales, máx 88 px, MIRANDO A LA IZQUIERDA)
│   │   ├── nino_helado.png          + nino_helado_n.png
│   │   ├── turista_selfie.png       + turista_selfie_n.png
│   │   ├── mimo_muro.png            + mimo_muro_n.png
│   │   ├── gaviota_mafiosa.png      + gaviota_mafiosa_n.png
│   │   ├── gato_guaton.png          + gato_guaton_n.png
│   │   ├── semaforo_rebelde.png     + semaforo_rebelde_n.png
│   │   ├── piscina_barro.png        + piscina_barro_n.png
│   │   └── fila_tramite.png         + fila_tramite_n.png
│   └── gags/                                                   (sombrero + 14 gags populares, máx 74 px)
│       ├── pudu_wizard_hat.png      + pudu_wizard_hat_n.png
│       ├── rain_cloud.png           + rain_cloud_n.png
│       ├── melted_icecream.png      + melted_icecream_n.png
│       ├── cucumber.png             + cucumber_n.png
│       ├── banana_peel.png          + banana_peel_n.png
│       ├── lightning_bolt.png       + lightning_bolt_n.png
│       ├── hair_dryer.png           + hair_dryer_n.png
│       ├── giant_fan.png            + giant_fan_n.png
│       ├── paint_bucket.png         + paint_bucket_n.png
│       ├── empanada.png             + empanada_n.png
│       ├── cardboard_box.png        + cardboard_box_n.png
│       ├── robot_vacuum.png         + robot_vacuum_n.png
│       ├── giant_anvil.png          + giant_anvil_n.png
│       ├── soap_bubbles.png         + soap_bubbles_n.png
│       └── vip_stamp.png            + vip_stamp_n.png
├── tiles/                                                      (pisos tileables, repeatWrap = true)
│   ├── grass_floor.png              + grass_floor_n.png
│   ├── stone_floor.png              + stone_floor_n.png
│   ├── desert_floor.png             + desert_floor_n.png
│   ├── mountain_floor.png           + mountain_floor_n.png
│   └── coast_floor.png              + coast_floor_n.png
├── ui/portraits/                                               (retratos HUD del Pudú y fauna)
│   ├── pudu_happy.png, pudu_shocked.png, pudu_angry.png
└── custom/                                                     (¡CARPETA VIP DEL ARTISTA!)
    └── <encounter_id>.png           + <encounter_id>_n.png     (sobrescribe al rival sin borrar el base)
```

### 2.2 Flujo para el Artista del Equipo (Sprites Propios + `_n.png` Automáticos + `[F5]`)

1. **Dibuja o exporta el PNG transparente (RGBA)** en Aseprite, Photoshop o Procreate (recomendado: contorno oscuro 1 px `#2B1B17`, enemigos mirando a la **izquierda**, altura/lado máximo ~88 px para encuentros y ~74 px para gags; si es más grande, luego lo escalas en vivo con `[F2]`).
2. **Guárdalo** en `assets/custom/<encounter_id>.png` (para probar sin sobreescribir) o en su ruta final (`assets/sprites/encounters/`, `assets/sprites/gags/`, `assets/tiles/`).
3. **Genera los mapas normales `_n.png` automáticamente en lote** con un solo comando (no toca tus PNG originales, solo crea/actualiza los `*_n.png` con el algoritmo Sobel + domo gaussiano `strength=2.4, dome_weight=0.45`):
   ```bash
   python3 tools/batch_normals.py assets/sprites assets/tiles assets/custom
   ```
   *(El algoritmo combina luminancia del dibujo + volumen tipo domo calculado con `GaussianBlur(2)` y `GaussianBlur(5)` del canal alfa, asignando `(128, 128, 255, 0)` a los píxeles transparentes para cero artefactos en el shader diferido HD-2D).*
4. **Pulsa `[F5]` dentro del juego abierto** (sin reiniciar): el juego re-lee el PNG y su `_n.png` directo desde el sistema de archivos y lo enciende bajo las luces HDR + Radiance Cascades.
5. **Calibra escala y posición en 10 segundos**: abre `[F2] → 3. GRÁFICA`, activa `Guías / Anclas`, ajusta `Escala Rival`, `Rival Offset X`, `Rival Offset Y`, y pulsa **`Guardar Ajustes`** (persiste en `stage_overrides.json`).

### 2.3 Si Faltan Rivales o Gags en la Hackathon (Generación IA en Lote)

Si al equipo le falta tiempo para dibujar algún rival o gag secundario, ejecuta los scripts de lote selectivo (nunca sobrescriben archivos existentes salvo con `--force`):

```bash
# Generar solo los encuentros/gags base que aún falten (con Gemini 2.5 Flash Image + limpieza chroma + _n.png)
python3 tools/generate_encounter_sprites.py --only mimo_muro fila_tramite

# Generar solo gags populares faltantes en assets/sprites/gags/ (con QA < 2% magenta residual)
python3 tools/generate_popular_gags.py --only empanada giant_anvil lightning_bolt

# Solo validar todos los pares diffuse + _n.png sin llamar a la API
python3 tools/generate_popular_gags.py --validate-only
```

### 2.4 Flujo para el Músico / Sonidista (Canción Propia + Lyria 3 Pro + 19 SFX)

| Necesidad | Qué usar | Cómo integrarlo sin drift en `beat_sync.lua` |
| :--- | :--- | :--- |
| **Canción principal hecha por el equipo** | Coloca tu `.wav` o `.ogg` (44100 Hz) en `assets/audio/battle_user_main.wav` | Mide su **BPM exacto** y **`beatOffset`** (instante exacto en segundos del primer golpe de compás) con el analizador DSP (`python3 tools/analyze_track_bpm.py assets/audio/battle_user_main.wav`) y actualiza `Audio.TRACK_META.user_battle` (ej. `bpm = 139.20, beats = 37, beatOffset = 0.342, loop = true`). `beat_sync.lua` aplica `(trackPos - beatOffset) * (bpm / 60)` con PLL suave para que el Pudú baile clavado al ritmo real de tu canción. |
| **Pistas instrumentales extra (Mapa, Plaza, Boss, Victoria)** | `python3 tools/generate_lyria3_music.py` (Vertex AI `global/lyria-3-pro-preview`) | Genera 5 pistas instrumentales sin voces (`superstar`, `boss`, `plaza`, `overworld`, `victory`), detecta BPM real y downbeat, corta múltiplos exactos de 4 compases con crossfade equal-power de `25 ms`, normaliza a `-1.5 dBFS`, exporta `.ogg` y guarda `assets/audio/lyria_tracks_meta.json` con los BPM medidos para `Audio.TRACK_META`. |
| **19 SFX cómicos y de ritual (+ 5 pistas offline de respaldo)** | `python3 tools/generate_battle_music.py` (100% local, Python + NumPy) | Genera en segundos los 10 SFX cómicos + 9 SFX de ritual/encuentro (y 5 pistas fallback WAV si no hay credenciales de Vertex AI ni canción del equipo). Cualquier SFX creado por el equipo se puede sustituir simplemente guardando un WAV con el mismo nombre en `assets/audio/`. |

---

## 3. División Codex vs Astra + Subagentes de esta Fase

| Rol | Herramienta | Propiedad de archivos (sin pisarse) | Responsabilidad principal |
| :--- | :--- | :--- | :--- |
| **Orquestador Principal** | **Codex** | `main.lua` (hot-reload `[F5]`, `loadAllSprites`, wiring de `[F2]`, `[F12]`, `[H]`, `stage_overrides.json`, pista inicial `user_battle` con fallback) | Lanza los 3 subagentes en paralelo, conecta `director_panel.lua` y `audio.lua` en `main.lua`, y verifica hot-reload + persistencia de overrides. |
| **Subagente 6A — Pipeline de Arte, Normales `_n.png` y Generadores IA** | **Subagente Codex** | `tools/batch_normals.py`, `tools/sprite_studio.py` (utilidades chroma + `generate_normal_map` + `trim_and_pad_sprite`), `tools/generate_encounter_sprites.py`, `tools/generate_popular_gags.py` | Implementa el conversor en lote de normales `_n.png` para sprites del artista y los generadores IA con limpieza magenta + QA automático. |
| **Subagente 6B — Motor de Audio (`audio.lua`), Analizador BPM y Generadores Musicales/SFX** | **Subagente Codex** | `audio.lua`, `tools/analyze_track_bpm.py`, `tools/generate_battle_music.py`, `tools/generate_lyria3_music.py` | Implementa `Audio` con `TRACK_META` (`user_battle` + 5 pistas), `getTrackState()` con `beatOffset`, 19 SFX + `playArrowChime()`, analizador de BPM/beatOffset para música propia, sintetizador de los 19 SFX y generador Lyria 3 Pro. |
| **Subagente 6C — Panel Director `[F2]`** | **Subagente Codex** | `director_panel.lua` | Construye la UI flotante de 3 pestañas (`1. ENCUENTROS`, `2. REACCIONES`, `3. GRÁFICA`), chips interactivos, steppers, telemetría HDR/GI/FPS, notificaciones toast y tabla completa de acciones hit-tested. |
| **Director de Arte, Audio & Demo Polish** | **Astra** | Solo lectura + auditoría en vivo con `[F2]` / `[F5]` / `[F12]` | Evalúa iluminación normal-mapped `_n.png` en los 4 presets (`Día`, `Atardecer`, `Noche`, `Teatral`), verifica sincronía exacta entre el baile del Pudú y el beat de la música, y audita la mezcla música vs SFX. |

---

## 4. Prompt Maestro para Codex (Copiar y Pegar — Orquestación con Subagentes)

```text
Actúa como Tech Lead de Pudú Fantasy (LÖVE2D 11.5 / Lua + herramientas Python) ejecutando la FASE 06: Pipeline de Arte HD-2D (_n.png), Música y 19 SFX, Hot-Reload [F5] y Panel Director [F2].

CONTEXTO ACTUAL:
La Fase 05 está completa (`battle_fx.lua`, `victory_album.lua`, `beat_sync.lua`, `stage_renderer.lua`, `lighting_pipeline.lua`, `encounters.lua`). Ahora necesitamos que el equipo de arte, música y diseño pueda iterar en vivo con sus propios assets o con generación IA en lote, y controlar toda la escena desde el Panel Director [F2].

LANZA 3 SUBAGENTES EN PARALELO (SIN COLISIÓN DE ARCHIVOS):
1. Subagente 6A (Arte & Normales): crea `tools/sprite_studio.py` (helpers `remove_magenta_chroma`, `trim_and_pad_sprite`, `generate_normal_map` con Sobel + domo gaussiano de alfa), `tools/batch_normals.py` (CLI para generar `*_n.png` en lote sobre cualquier carpeta de sprites 2D del artista sin tocar los originales), `tools/generate_encounter_sprites.py` y `tools/generate_popular_gags.py` (generación en lote con Vertex AI `global/gemini-2.5-flash-image` + limpieza chroma `#FF00FF` + flood-fill esquinas + despill + QA `< 2%` magenta + `_n.png`).
2. Subagente 6B (Audio & SFX): crea `audio.lua` (carga `"static"` zero-drift con `TRACK_META` incluyendo `user_battle` con `bpm` + `beatOffset` + 5 pistas Lyria/fallback, `getTrackState()`, `play()` con clonado y pitch jitter, `playArrowChime(stepIndex)` pentatónica C5..C7 y aliases cortos sin `sfx_`), `tools/generate_battle_music.py` (sintetizador NumPy 44100Hz 16-bit de los 19 SFX cómicos/rituales + 5 pistas fallback), `tools/generate_lyria3_music.py` (Vertex AI `global/lyria-3-pro-preview` + DSP de BPM/downbeat + corte a múltiplos de 4 compases con crossfade 25ms + exportación OGG) y `tools/analyze_track_bpm.py` (CLI rápido que analiza cualquier WAV/OGG/MP3 del equipo e imprime el bloque Lua exacto `{ bpm, beats, beatOffset }` para `Audio.TRACK_META.user_battle`).
3. Subagente 6C (Panel Director): crea `director_panel.lua` con el panel derecho (`width = 368`) de 3 pestañas (`1. ENCUENTROS`, `2. REACCIONES`, `3. GRÁFICA`), los 9 encuentros con filtros, 4 biomas, selector musical + pausa de beat, 14 reacciones forzadas, 4 poses del Pudú, 4 botones de Super-Combo en 1 clic (`__COMBO_ELECTRO__`, `__COMBO_FREEZE__`, `__COMBO_STEAM__`, `__COMBO_SLIP__`) + prueba de flechas, 9 temas de escenario, 4 presets de luz, 5 climas, 6 steppers (zoom, escalas, offsets, baile), 6 toggles (Deferred, Guías, GI, Bloom, Sombras, HUD `[H]`), telemetría HDR/GI/FPS y botones `[F5]`, `Guardar Ajustes`, `[F12]`.

CUANDO LOS 3 SUBAGENTES TERMINEN, TÚ (ORQUESTADOR) INTEGRARÁS EN `main.lua`:
1. Carga y **Live Hot-Reload `[F5]`** (compatible con modo unfused y `.exe` fused):
   - `loadImageRaw(path, repeatWrap)` leyendo bytes directos desde `getExternalBaseDir() .. "/" .. path` con `io.open(..., "rb")` → `love.filesystem.newFileData` → `love.graphics.newImage`, filtro `nearest` (y `repeat` en tiles), fallback a `love.filesystem`.
   - `loadSpritePair(basePath, repeatWrap)` cargando `.png` y `_n.png`.
   - `loadAllSprites()` priorizando `assets/custom/<enc.id>` sobre `enc.sprite` para cada encuentro, cargando `pudu_8dir_sheet`, `pudu_wizard_hat`, retratos, 5 tiles, 14 gags y props.
   - Al pulsar `f5` (o botón `reload_sprites` del Director): ejecuta `loadAllSprites()`, `stage:setTiles(assets.tiles)` y muestra confirmación en HUD y toast.
2. Cableado completo del Panel Director (`[F2]`):
   - `love.keypressed`: `f2` alterna `director.open`; `f5` recarga sprites; `f12` guarda captura en `screenshots/pudu_fantasy_YYYYMMDD_HHMMSS.png`; `h` alterna `hud.hidden`; `m` alterna música.
   - `love.mousepressed`: priorizar Álbum (`[J]`), luego `director:containsPoint` / `director:hitTest` → `handleDirectorAction(btnId, payload)` cubriendo TODAS las acciones de las 3 pestañas, incluyendo los 4 botones de Super-Combo (`triggerComboSpectacle` + daño crítico demo), `force_reaction` (con SFX y globo), `warp_biome`, `set_track` (reseteando `beatSync`), steppers de `stage.camZoom`, `Game.puduScale`, `mutateEncounterTransform` y `saveCurrentOverrides()` hacia `stage_overrides.json`.
   - Al iniciar el juego, llamar `applyLoadedOverrides()` para cargar `stage_overrides.json`.
3. Ejecutar `python3 tools/generate_battle_music.py` para garantizar que los 19 SFX existan en `assets/audio/` desde el primer minuto, y verificar que LÖVE arranca limpio, `[F2]`, `[F5]`, `[H]` y `[F12]` funcionan y `stage_overrides.json` guarda y recarga sin errores.

Entrega resumen de archivos, comandos listos para el artista/músico y resultado de verificación.
```

---

## 5. Prompts Individuales por Subagente

### Subagente 6A — Pipeline de Arte, Mapas Normales `_n.png` y Generadores IA

```text
Implementa las herramientas de pipeline de sprites HD-2D para Pudú Fantasy en `tools/`:

1. `tools/sprite_studio.py` (librería base + helpers reutilizables):
   - `load_dotenv(env_path)` para leer `.env` sin dependencias extra.
   - `remove_magenta_chroma(img, tolerance=125.0, keep_purple=False)`: elimina fondo chroma `#FF00FF` protegiendo tonos púrpuras legítimos cuando `keep_purple=True`.
   - `trim_and_pad_sprite(img, target_max_dim, pad=2, anchor_bottom=True)`: recorta al bounding box opaco, escala con `Image.Resampling.NEAREST` a `<= target_max_dim` y centra anclando pies abajo.
   - `generate_normal_map(img, strength=2.4, dome_weight=0.45, invert_y=False)`:
     - Calcula luminancia `0.299 R + 0.587 G + 0.114 B`.
     - Calcula mapa de altura tipo domo desde el canal alfa usando mezcla de `GaussianBlur(radius=2.0)` (55%) y `GaussianBlur(radius=5.0)` (45%).
     - Combina `height = lum * (1 - dome_weight) + dome * dome_weight`, aplica operador Sobel `gx, gy`, normaliza `(nx, ny, nz)` a RGB `[0..255]`, asigna alfa `255` donde `alpha > 0.1` y fija `(128, 128, 255, 0)` en píxeles transparentes.

2. `tools/batch_normals.py` (CLI ultrarrápido para el artista del equipo):
   - Acepta una o varias carpetas/archivos PNG (`python3 tools/batch_normals.py assets/sprites assets/tiles assets/custom`).
   - Recorre recursivamente ignorando archivos que ya terminen en `_n.png` o `light_radial.png` / `shadow_mask.png`.
   - Soporta `--force` (por defecto regenera si el `.png` fuente es más nuevo que el `_n.png` o si falta el `_n.png`), `--strength` (default 2.4) y `--dome` (default 0.45).
   - Imprime tabla limpia con cada `_n.png` generado/actualizado y tiempo total.

3. `tools/generate_encounter_sprites.py` y `tools/generate_popular_gags.py`:
   - Usan Vertex AI `global/gemini-2.5-flash-image` (con token `gcloud auth application-default print-access-token` y fallback opcional a `GEMINI_API_KEY`) enviando `assets/sprites/pudu_hero.png` sobre lienzo `#FF00FF` como referencia de estilo 16-bit HD-2D.
   - `generate_encounter_sprites.py`: define los 8 encuentros (todos mirando a la IZQUIERDA, `target_max_dim=88`: `nino_helado`, `turista_selfie`, `mimo_muro`, `gaviota_mafiosa`, `gato_guaton`, `semaforo_rebelde`, `piscina_barro`, `fila_tramite`) + 4 gags base (`rain_cloud`, `melted_icecream`, `cucumber`, `banana_peel`, `target_max_dim=74`).
   - `generate_popular_gags.py`: define 10 gags populares (`lightning_bolt`, `hair_dryer`, `giant_fan`, `paint_bucket`, `empanada`, `cardboard_box`, `robot_vacuum`, `giant_anvil`, `soap_bubbles`, `vip_stamp`, `target_max_dim=74`).
   - Post-proceso: `remove_magenta_chroma` → flood-fill BFS desde las 4 esquinas (`color_tol=52`) → despill del halo magenta exterior → `trim_and_pad_sprite` → `generate_normal_map`.
   - QA programático (`validate_gag_pair` / `--validate-only`): valida RGBA, esquinas 100% transparentes, proporción opaca `[0.15, 0.85]`, magenta residual `< 2%` y coincidencia exacta de dimensiones/alfa entre diffuse y `_n.png`, con hasta 3 reintentos automáticos y `--only` + `--force` + `ThreadPoolExecutor` con rate-limit cooperativo.

Verifica sintaxis con `python3 -m py_compile tools/*.py` y prueba `tools/batch_normals.py` sobre un PNG de prueba (o los existentes).
```

### Subagente 6B — Motor de Audio (`audio.lua`), Analizador BPM, Lyria 3 Pro y 19 SFX

```text
Implementa el sistema de audio y herramientas sonoras de Pudú Fantasy:

1. `audio.lua` (LÖVE2D 11.5):
   - `Audio.TRACK_META` con 6 entradas:
     - `user_battle`: `assets/audio/battle_user_main.wav`, `bpm = 139.20`, `beats = 37`, `beatOffset = 0.342`, `loop = true` (canción principal del equipo).
     - `overworld` (`battle_overworld_lyria.ogg`, 116.04 BPM, 64 beats, loop true)
     - `superstar` (`battle_superstar_lyria.ogg`, 132.01 BPM, 64 beats, loop true)
     - `boss` (`battle_boss_lyria.ogg`, 141.16 BPM, 64 beats, loop true)
     - `plaza` (`battle_plaza_lyria.ogg`, 120.00 BPM, 64 beats, loop true)
     - `victory` (`battle_victory_lyria.ogg`, 136.84 BPM, 32 beats, loop false)
     - Si falta un `.ogg` de Lyria, soporta fallback automático a la versión WAV procedural (`battle_superstar_132.wav`, etc.) para que el juego nunca quede mudo.
   - Carga todas las pistas de música y SFX en modo `"static"` para precisión de muestra en `source:tell("seconds")`. Cuando está silenciado/desactivado mantiene la pista corriendo a volumen `0.0` para no perder el pulso del compás.
   - `Audio:getTrackState()` retorna `{ trackId, id, bpm, beatOffset, pos, duration, playing, paused }`.
   - `SFX_FILES`: registra los 19 SFX cómicos y de ritual (`sfx_cry_wah`, `sfx_splat`, `sfx_boing`, `sfx_laugh`, `sfx_camera_flash`, `sfx_horn`, `sfx_rimshot`, `sfx_rain_pour`, `sfx_meow_scared`, `sfx_seagull`, `sfx_spell_arrow_1..6`, `sfx_spell_miss`, `sfx_spell_unleash`, `sfx_encounter_start`) más SFX clásicos de combate/UI (`victory`, `hurt`, `heal`, `dash`, `bash_impact`, `water_rush`, `stomp`, `chime_1..3`, `orb_gain`, `parry_clash`, etc.) con alias corto automático sin prefijo `sfx_`.
   - `Audio:play(id, volume, pitchJitter, basePitch)`: clona la fuente (`base:clone()`) para polifonía limpia, aplica `sfxVolume` y jitter de tono acotado `[0.25, 4.0]`.
   - `Audio:playArrowChime(stepIndex)`: toca `sfx_spell_arrow_1..6` (C5, D5, E5, G5, A5, C6); para pasos 7..11+ escala `sfx_spell_arrow_6` en pentatónica ascendente (D6, E6, G6, A6, C7).
   - Incluye `playTrack`, `setTrackPaused`, `setMusicVolume`, `toggleMusic`, `toggleMute`, `stopAll`.

2. `tools/generate_battle_music.py` (solo Python stdlib + NumPy, 44100 Hz 16-bit PCM):
   - Genera los 19 SFX WAV en `assets/audio/`:
     - 10 cómicos expresivos: `sfx_cry_wah`, `sfx_splat`, `sfx_boing`, `sfx_laugh`, `sfx_camera_flash`, `sfx_horn`, `sfx_rimshot`, `sfx_rain_pour`, `sfx_meow_scared`, `sfx_seagull`.
     - 9 de ritual y encuentro: `sfx_spell_arrow_1..6` (campana/arpa cristalina C5, D5, E5, G5, A5, C6 con shimmer estéreo), `sfx_spell_miss` (bloop amigable), `sfx_spell_unleash` (acorde Cmaj9 brillante + whoosh), `sfx_encounter_start` (swirl dramático + arpegio + fanfarria Fmaj7).
   - Genera también 5 pistas WAV de respaldo con longitud exacta en muestras (`beat_samples(bpm, beats)`) para loop sin drift.

3. `tools/generate_lyria3_music.py` (Vertex AI `global/lyria-3-pro-preview` + DSP con NumPy/SciPy + ffmpeg):
   - Genera las 5 pistas instrumentales (`superstar`, `boss`, `plaza`, `overworld`, `victory`) guardando crudos en `assets/audio/lyria_raw/` (reutiliza caché salvo `--force`, y soporta `--reprocess-only` / `--only`).
   - Analiza BPM exacto y fase del downbeat mediante flujo espectral multi-banda, selecciona la ventana más sólida en múltiplos de 4 compases, aplica crossfade equal-power de `25 ms` en el empalme de loop, normaliza a `-1.5 dBFS`, exporta `.ogg` Vorbis y escribe `assets/audio/lyria_tracks_meta.json` con error de beat-lock en milisegundos.

4. `tools/analyze_track_bpm.py`:
   - CLI simple que recibe cualquier archivo de audio del equipo (`python3 tools/analyze_track_bpm.py assets/audio/battle_user_main.wav [--target-bpm 138]`), reutiliza la detección de onsets/BPM/downbeat y muestra exactamente el snippet Lua listo para pegar en `Audio.TRACK_META.user_battle` (`bpm`, `beats`, `beatOffset`, `duration` y error medio en ms).

Verifica sintaxis de todos los scripts Python (`py_compile`) y ejecuta `python3 tools/generate_battle_music.py` para comprobar que se generan los 19 SFX sin clipping.
```

### Subagente 6C — Panel Director de Estudio (`director_panel.lua`, `[F2]`)

```text
Crea el archivo `director_panel.lua` para Pudú Fantasy (LÖVE2D 11.5): el Panel Director de Producción y Gráfica activado con `[F2]`.

REQUISITOS COMPLETOS:
1. Diseño visual y ergonomía:
   - Panel lateral derecho flotante (`width = 368`, `px = screenW - width - 12`, `py = 50`, `ph = screenH - 64`) con fondo translúcido oscuro `(0.05, 0.06, 0.12, 0.94)` y borde lila suave.
   - Encabezado `"DIRECTOR DE ENFRENTAMIENTOS"` + botón cerrar `"X"` (`close_panel`).
   - 3 pestañas superiores: `"1. ENCUENTROS"` (`encuentros`), `"2. REACCIONES"` (`reacciones`), `"3. GRÁFICA"` (`grafica`).
   - Sistema de notificaciones toast abajo del panel (`notify(msg)`, `update(dt)`, duración `2.6s`).
   - Hit-testing limpio: `containsPoint(mx, my, screenW, screenH)` y `hitTest(mx, my) -> btnId, payload`.

2. Pestaña `1. ENCUENTROS`:
   - Filtro por categoría: `Todos` (`todos`), `Personas` (`persona`), `Animales` (`animal`), `Desafíos` (`desafio`).
   - Lista de los **9 encuentros** (`ctx.encountersList`) mostrando índice, badge `[P]`/`[A]`/`[D]`, nombre y `[OK]` si está vencido (`jump_encounter`, payload = índice).
   - Toggles: `Modo: BATALLA / MAPA` (`toggle_mode`), `IA: Google Vivo / Prueba 0ms` (`toggle_mock`), `Reiniciar Rival` (`reset_battle`), `Curar Todo` (`heal_all`).
   - Fila **EXPLORAR BIOMA (MAPA)** con 4 botones de teletransporte: `Bosque` (`bosque`), `Desierto` (`desierto`), `Costa` (`costa`), `Ciudad` (`ciudad`) (`warp_biome`).
   - Selector **MÚSICA DE BATALLA & COMPÁS**: `Tu Canción` (`user_battle`), `Lyria Batalla` (`superstar`), `Lyria Boss` (`boss`), `Lyria Plaza` (`plaza`), `Lyria Mapa` (`overworld`) (`set_track`) + botón `Pausar / Reanudar` beat (`toggle_beat_pause`).

3. Pestaña `2. REACCIONES`:
   - Grilla 3 columnas con las **14 reacciones forzadas** (`force_reaction`): `idle` (Normal), `crying` (Llorando), `laughing` (Riendo), `angry` (Furioso), `scared` (Asustado), `shocked` (Shock !!), `wet` (Mojado), `frozen` (Congelado), `dizzy` (Mareado), `distracted` (Distraído), `splatted` (Aplastado), `happy_pacified` (Feliz), `chased` (Huyendo), `defeated` (Derrotado).
   - Grilla 2×2 de **poses del Pudú** (`force_pudu_pose`): `battle_idle` (Baile Compás), `ritual` (Conjuro), `victory` (Giro Victoria), `hurt` (Shock).
   - Grilla 2×3 de **Disparadores rápidos / Super-Combos en 1 clic** (`quick_gag`):
     - `Lluvia + Llanto` (`"nube de lluvia"`)
     - `Combo Electro` (`"__COMBO_ELECTRO__"`)
     - `Combo Hielo` (`"__COMBO_FREEZE__"`)
     - `Combo Vapor` (`"__COMBO_STEAM__"`)
     - `Combo Resbalón` (`"__COMBO_SLIP__"`)
     - `Probar Flechas` (`"__TEST_RITUAL__"`)
   - Botón `Limpiar Props & Partículas` (`clear_fx`).

4. Pestaña `3. GRÁFICA`:
   - Override de escenario (`set_stage`): `Auto` (`__AUTO__`), `Plaza`, `Mirador`, `Muelle`, `Vereda`, `Bosque`, `Esquina`, `Pantano`, `Oficina`.
   - 4 presets de **Iluminación HD-2D** (`set_light`): `Día` (`dia`), `Atardecer` (`atardecer`), `Noche` (`noche`), `Teatral` (`dramatico`).
   - 5 **Climas ambientales** (`set_weather`): `Limpio` (`none`), `Lluvia` (`rain`), `Nieve` (`snow`), `Pétalos` (`petals`), `Confeti` (`confetti`).
   - 6 **Steppers `- / valor / +`**: `Zoom Cámara` (`zoom_dec`/`zoom_inc`), `Escala Pudú` (`pudu_sc_dec`/`pudu_sc_inc`), `Escala Rival` (`enemy_sc_dec`/`enemy_sc_inc`), `Rival Offset X` (`enemy_x_dec`/`enemy_x_inc`), `Rival Offset Y` (`enemy_y_dec`/`enemy_y_inc`), `Intensidad Baile` (`dance_dec`/`dance_inc`).
   - 6 **Toggles**: `Deferred HD-2D` (`toggle_shader`), `Guías / Anclas` (`toggle_guides`), `GI 2D (Cascades)` (`toggle_gi`), `Bloom HDR + ACES` (`toggle_bloom`), `Sombras Suaves` (`toggle_shadows`), `Ocultar HUD [H]` (`toggle_hud`).
   - Badge de telemetría HDR/GI/FPS en vivo cuando exista `ctx.lightingStats`.
   - Acciones de artista: `Recargar Sprites PNG [F5]` (`reload_sprites`), `Guardar Ajustes` (`save_overrides`), `Captura [F12]` (`take_screenshot`).

Usa únicamente `fonts.med`, `fonts.small`, `fonts.tiny` recibidas en `DirectorPanel.new(fonts)` y mantén todos los controles cabiendo cómodamente en `1280×720`.
```

---

## 6. Prompt para Astra (Auditoría Visual Zero-Overlap & Polish Artístico/Sonoro)

Usa este prompt con **Astra** al terminar la integración, adjuntando capturas sacadas con `[F12]` bajo 2 presets de iluminación (`Día` y `Noche`/`Teatral`), una captura con `[F2]` abierto y la salida de consola de `validate-only` + análisis BPM:

```text
Actúa como Art, Audio & Tools Director (Astra) auditando la FASE 06 de Pudú Fantasy (Sprites + Mapas Normales `_n.png`, Música & 19 SFX, Hot-Reload `[F5]` y Panel Director `[F2]`).

Audita el pipeline y las capturas adjuntas en 4 ejes:

1. CALIDAD DE ARTE HD-2D Y MAPAS NORMALES (`_n.png`):
   - Sobre los sprites del artista (y/o los generados con IA): ¿los mapas normales `_n.png` generan volumen limpio y cálido bajo los presets `Día`, `Atardecer`, `Noche` y `Teatral`, sin bordes dentados ni halos magenta residuales?
   - ¿El filtro `nearest` se mantiene intacto en sprites y tiles, y todos los rivales miran hacia la IZQUIERDA (hacia el Pudú) con sus pies bien apoyados sobre la línea de contacto (`Guías / Anclas` en `[F2]`)?
   - ¿Existe coherencia de escala entre el Pudú y los 9 rivales tras guardar `stage_overrides.json`?

2. AUDITORÍA SONORA Y SINCRONÍA DE COMPÁS (`beat_sync.lua` + `audio.lua`):
   - ¿La pista principal (`user_battle` o `superstar`) hace que el baile idle del Pudú y el rebote del sombrero caigan clavados en el downbeat (sin desfase perceptible tras 2–3 loops completos)?
   - ¿La jerarquía de mezcla (`musicVolume ~0.52`, `sfxVolume ~0.80`) permite escuchar con claridad las 6 campanas pentatónicas del ritual (`sfx_spell_arrow_1..6`), el destello `sfx_spell_unleash` y los 10 SFX cómicos sin distorsión ni clipping?
   - ¿Hay algún click audible en el punto de loop de las pistas `.wav`/`.ogg`?

3. ERGONOMÍA Y ZERO-OVERLAP DEL PANEL DIRECTOR (`[F2]`):
   - En `1280×720`, ¿las 3 pestañas de `director_panel.lua` caben sin recortar botones en el borde inferior ni pisar el centro del escenario donde el artista evalúa al rival?
   - ¿Ocultar HUD (`[H]`) + Captura (`[F12]`) produce screenshots dignos de portada/presentación para el jurado?

4. FLUJO DEL ARTISTA (`[F5]`):
   - ¿El ciclo "editar PNG → `batch_normals.py` → pulsar `[F5]` → ajustar en `[F2]` → `Guardar Ajustes`" toma menos de 15 segundos y persiste tras reiniciar?

ENTREGA TU REPORTE EN 3 BLOQUES:
- [AJUSTES CRÍTICOS]: problemas de normal maps, chroma, desfase de BPM, clipping o recorte del panel `[F2]`.
- [CALIBRACIONES FINAS]: valores recomendados de `stage_overrides.json` (escala/offset por rival, `strength`/`dome_weight` de normales o balance de volumen).
- [VEREDICTO]: LISTO PARA FASE 07 (EMPAQUETADO Y DEMO) / REQUIERE RETOQUE.
```

---

## 7. Gate de Iteración en Equipo (Playtest de 5 min + Definition of Done)

Realiza esta validación en equipo (programador + artista + músico) antes de pasar a la **Fase 07 (QA Final, Build Fused y Demo del Jurado)**:

### Guion de Playtest en Vivo (5 minutos)
1. **Minuto 0–1.5 (Test real del Artista — `[F5]` + `_n.png` + `stage_overrides.json`)**:
   - Toma 1 sprite de rival (o copia uno a `assets/custom/nino_helado.png`), hazle un cambio visible en el editor de imagen, ejecuta `python3 tools/batch_normals.py assets/custom` y pulsa **`[F5]`** con el juego corriendo.
   - Verifica que el sprite se actualiza al instante sin reiniciar y reacciona al cambiar la luz en `[F2] → 3. GRÁFICA` (`Día` → `Noche` → `Teatral`). Ajusta `Escala Rival` / `Offset Y` con `Guías / Anclas` activadas, pulsa **`Guardar Ajustes`**, reinicia el juego y confirma que la calibración se conservó.
2. **Minuto 1.5–3 (Test real del Músico — Ritmo + 19 SFX)**:
   - Desde `[F2] → 1. ENCUENTROS`, alterna entre **`Tu Canción`** (`user_battle`) y las pistas `Lyria Batalla` / `Boss` / `Mapa`. Observa el rebote del Pudú durante 20 segundos: debe mantenerse pegado al pulso y pausarse/reanudarse limpiamente con `Pausar`.
   - En `[F2] → 2. REACCIONES`, pulsa `Probar Flechas` y acierta 6+ flechas seguidas para verificar la escala pentatónica ascendente (`C5 → C6 → C7`) y el chime de liberación.
3. **Minuto 3–4 (Showroom de 1 Clic en `[F2]`)**:
   - Prueba los 4 botones de Super-Combo (`Combo Electro`, `Combo Hielo`, `Combo Vapor`, `Combo Resbalón`), fuerza 3 reacciones (`Llorando`, `Furioso`, `Congelado`) y teletranspórtate a los 4 biomas (`Bosque`, `Desierto`, `Costa`, `Ciudad`).
4. **Minuto 4–5 (Modo Portada `[H]` + `[F12]`)**:
   - Cierra `[F2]`, pulsa `[H]` para ocultar el HUD y pulsa `[F12]`. Abre el PNG creado en `screenshots/` y comprueba que está limpio, nítido y listo para slides de la hackathon.

### Definition of Done (Checklist de salida de Fase 06)
- [ ] **Pipeline de Arte del Equipo listo**: carpetas `assets/sprites/{encounters,gags}`, `assets/tiles/`, `assets/ui/portraits/` y `assets/custom/` operativas; `tools/batch_normals.py` genera `*_n.png` válidos con iluminación HD-2D real.
- [ ] **Hot-Reload `[F5]` probado en vivo**: actualiza PNGs y tiles desde disco sin reiniciar el proceso de LÖVE2D.
- [ ] **Generadores IA listos bajo demanda**: `generate_encounter_sprites.py` y `generate_popular_gags.py` pasan `py_compile` y `--validate-only` (y nunca pisan arte propio sin `--force`).
- [ ] **Audio y Ritmo sincronizados**: `audio.lua` carga música `"static"` con `bpm` y `beatOffset` exactos (`user_battle` + 5 pistas), `beat_sync.lua` baila sin drift, los 19 SFX cómicos/rituales existen en `assets/audio/` y `playArrowChime()` escala limpiamente.
- [ ] **Panel Director `[F2]` completo**: las 3 pestañas funcionan sin recortes en `1280×720` (9 encuentros, 4 biomas, 14 reacciones, 4 poses, 4 Super-Combos en 1 clic, 9 escenarios, 4 luces, 5 climas, 6 steppers, 6 toggles, telemetría HDR/GI/FPS, `[F5]`, guardar `stage_overrides.json`, `[H]` y `[F12]`).
- [ ] **Veredicto de Astra**: iluminación `_n.png`, mezcla sonora y capturas `[F12]` aprobadas para pasar a la Fase 07.
