# AGENTS.md — Pudú Fantasy

> **Ley del repositorio:** Todas las reglas, contratos de módulos, convenciones de assets y protocolos de verificación aquí definidos son vinculantes para cualquier agente o subagente que modifique este proyecto.
>
> **Modo inicial del equipo: Modo B (Greybox -> Drop-In)** — El juego arranca y es 100% jugable/testeable sin PNGs ni audios finales gracias a los placeholders procedurales de `asset_loader.lua` y la degradación silenciosa de `audio.lua`. Se puede escalar a **Modo A** en cualquier momento colocando archivos reales en `assets/` o `assets/custom/` y presionando **`[F5]`** (para sprites/tiles en caliente) o reiniciando (para audio).

---

## 1. Identidad del Proyecto y Arquitectura de Carpetas

**Nombre:** **Pudú Fantasy — Batallas de Prompts al Compás**  
**Género:** RPG humorístico HD-2D por turnos (inspirado en *Final Fantasy* + expresividad rítmica idle de *Mario & Luigi: Superstar Saga*) donde el jugador vence a 4 rivales cómicos, uno por bioma, escribiendo **cualquier prompt libre**.
**Motor y Stack:**
- **Cliente de juego:** **LÖVE2D 11.5** (LuaJIT, `1280×720` base, compilable a `.love` y `.exe` Win64 portable).
- **Puente IA opcional (local):** **Python 3.10+** (`ai_bridge.py` en `http://127.0.0.1:18425`, compatible con **Vertex AI ADC** y **Gemini API Key**):
  - Etapa 1 (Juicio cómico rápido): `gemini-2.5-flash` con `thinkingBudget=0`, TLS persistente y `responseSchema` estricto de **34 campos JSON**.
  - Etapa 2 (Sprite HD-2D en vivo, lanzamiento paralelo especulativo): `gemini-2.5-flash-image` + recorte alfa + mapa de normales Sobel (`_n.png`).
- **Modo 100% Offline / Standalone:** `battle_worker.lua` incluye un motor de respaldo completo en Lua puro (los 4 encuentros de campaña, 5 combates de QA y 6 Super-Combos de 2 turnos + sanitizador anti-trampas) que responde en **0 ms** cuando no hay puente Python ni WiFi.

### Estructura de carpetas del repositorio

```text
Pudu-hackaton/
├── AGENTS.md                       # Este documento (ley del repositorio)
├── conf.lua                        # Configuración LÖVE2D 11.5 (1280x720, msaa=0, highdpi=false)
├── main.lua                        # Integrador principal: ciclo love.*, máquina de estados, CLI, workers
├── asset_loader.lua                # Carga dual Fused/Unfused (diff + _n normal map), greybox Modo B y hot-reload [F5]
├── json.lua                        # Codificador/decodificador JSON UTF-8 puro en LuaJIT
├── encounters.lua                  # 4 biomas (↗), 4 rivales de campaña, temas de escenario, semiHintLine, overrides I/O
├── stage_renderer.lua              # Mapa diagonal ↗, relieve 3D, cámara calma room-snapped, arena batalla, minimapa
├── shaders.lua                     # Shaders GLSL (MRT G-Buffer, JFA SDF, 5-Cascade Radiance GI, Dual-Kawase Bloom, ACES, fallback)
├── lighting_pipeline.lua           # Orquestador GPU Deferred 2D + 2D GI + HDR Bloom + estadísticas [PERF]
├── audio.lua                       # Música con metadata exacta (BPM, beats, beatOffset) y catálogo SFX con degradación segura
├── beat_sync.lua                   # PLL sin deriva sobre source:tell("seconds") + baile idle Pudú + física del sombrero
├── spell_ritual.lua                # Minijuego de flechas luminosas convexas (carga de poder mientras responde la IA)
├── battle_fx.lua                   # Invocaciones, partículas, burbujas, textos flotantes zero-overlap, combos y finales cómicos
├── battle_hud.lua                  # HUD minimalista estilo Final Fantasy (strip 78px, barra rival diegética, cero spoilers)
├── director_panel.lua              # Panel Director [F2] para artistas/QA (biomas, reacciones, luz, escala, combos)
├── battle_worker.lua               # Hilo LÖVE2D HTTP hacia /battle_prompt + fallback offline completo
├── sprite_worker.lua               # Hilo LÖVE2D HTTP hacia /sprite (decodificación base64 -> Image + normal map)
├── ai_bridge.py                    # Servidor HTTP local 127.0.0.1:18425 (Vertex AI / Gemini API + caché RAM/disco)
├── run.sh                          # Lanzador macOS/Linux (detecta LÖVE 11.5, levanta ai_bridge.py si existe + cleanup trap)
├── run_windows.ps1 / Jugar_Windows.bat
├── requirements.txt / .env.example
├── assets/
│   ├── fonts/PTSans.ttc            # Fuente empaquetada obligatoria (fallback a fuente LÖVE en Modo B)
│   ├── audio/                      # battle_user_main.wav + pistas *_lyria.ogg + SFX *.wav
│   ├── tiles/                      # 5 suelos repetibles (grass, stone, desert, mountain, coast: *.png + *_n.png)
│   ├── sprites/                    # pudu_8dir_sheet (6x8), light_radial, props, encounters/, gags/ (pudu_wizard_hat)
│   ├── ui/portraits/               # pudu_happy.png, pudu_shocked.png, pudu_angry.png
│   └── custom/                     # Drop-in de artistas con prioridad sobre sprites/ y recarga en vivo [F5]
├── tools/
│   ├── sprite_studio.py            # Limpieza magenta, normal map Sobel (generate_normal_map), previews
│   ├── build_windows_exe.py        # Empaquetador PuduFantasy.love + PuduFantasy.exe + PuduFantasy-Windows-x64.zip
│   └── love-win64/                 # Binarios LÖVE2D 11.5 Win64 (love.exe + 7 DLLs)
├── cache/sprites/                  # Caché persistente de sprites generados en vivo (no versionar pesados)
├── screenshots/                    # Capturas [F12] y batería QA CLI
└── dist/                           # Artefactos de entrega (.love, PuduFantasy-Windows/, .zip)
```

---

## 2. Contratos de Módulos y Estrategia de Assets (Modo B -> Modo A)

### 2.1 Contrato de `asset_loader.lua`

`asset_loader.lua` centraliza toda carga de imágenes, normal maps, overrides de artistas y fallbacks procedurales:
- **API pública obligatoria:**
  - `AssetLoader.loadAll(encountersList)` -> retorna tabla de assets cargados (`pudu`, `puduQuads`, `wizardHat`, `tiles`, `lightRadial`, `portraits`, `encounters`, `gags`, `props`, `stats = { realCount, placeholderCount, customCount, mode }`).
  - `AssetLoader.loadImageRaw(path, repeatWrap)` -> intenta primero lectura externa desde `AssetLoader.getExternalBaseDir()` (`io.open(..., "rb")` -> `love.filesystem.newFileData`) y luego `love.filesystem.getInfo`; aplica `setFilter("nearest", "nearest")` (salvo `light_radial.png`, que usa `"linear"`) y `setWrap("repeat", "repeat")` si `repeatWrap == true`.
  - `AssetLoader.loadSpritePair(basePath, repeatWrap)` -> busca `assets/custom/` con prioridad, carga `{ diff, norm, isPlaceholder }`, buscando automáticamente el normal map hermano `<nombre>_n.png` (`norm = nil` si no existe, cayendo a normal plana `(0, 0, 1)` en shader).
  - `AssetLoader.buildQuads(img, cols, rows)` -> construye la matriz `quads[row][col]` con indexación exacta:
    - **`row = 0..rows-1`** (para `pudu_8dir_sheet`, `cols = 6, rows = 8`: `0=S, 1=SE, 2=E, 3=NE, 4=N, 5=NW, 6=W, 7=SW`).
    - **`col = 1..cols`** (frames de animación 1-indexados).
  - `AssetLoader.getExternalBaseDir()` -> devuelve la carpeta base real en disco tanto en ejecución unfused como fused (`love.filesystem.getSourceBaseDirectory()`), permitiendo hot-reload `[F5]` incluso desde un `.exe`.
- **Fallback automático Modo B:** si falta un archivo en `assets/`, genera texturas procedurales legibles vía `love.image.newImageData` (`pudu_8dir_sheet` `6×8`, `pudu_wizard_hat`, 5 tiles repetibles, `light_radial` gaussiano `linear`, retratos y siluetas de encuentros/props), marcando `isPlaceholder = true` y contabilizando en `assets.stats`.

### 2.2 Contratos del resto de módulos

| Módulo | Responsabilidad y superficie principal |
|---|---|
| `conf.lua` | Configura LÖVE2D `11.5`, `identity = "pudu_fantasy_battle"`, `1280×720` (`minwidth=960`, `minheight=540`, `resizable=true`, `vsync=1`, `msaa=0`, `highdpi=false`), deshabilita `joystick`, `physics`, `touch`, `video`. |
| `main.lua` | Integrador único de callbacks `love.*`, `love.errorhandler` con salida `exit 1` bajo `--quit-after=`, `parseCliArgs` (`%-%-`), hot-reload `[F5]`, captura `--screenshot` y despacho a módulos. |
| `json.lua` | `json.encode(val)` y `json.decode(str)` UTF-8 sin dependencias externas para LuaJIT. |
| `audio.lua` | `Audio.new(muted)` + `Audio.TRACK_META` (`user_battle` `139.20 BPM`/`beatOffset=0.342`, `overworld` `116.04`, `superstar` `132.01`, `boss` `141.16`, `plaza` `120.00`, `victory` `136.84`). Carga `"static"` protegida con `pcall`; si faltan archivos los guarda en `self.missing` sin crash. En mute mantiene el `Source` corriendo a volumen `0.0` para preservar `source:tell("seconds")`. Expone `playTrack`, `getTrackState`, `play`, `setTrackPaused`, `setMusicVolume`, `toggleMusic`, `toggleMute`, `stopAll`. |
| `encounters.lua` | Definición de los 4 biomas (`desierto`, `costa`, `montana`, `chiloe`), 4 rivales de campaña, temas de escenario, `semiHintLine` y lectura/escritura de overrides. |
| `stage_renderer.lua` | Overworld diagonal `↗`, relieve 3D, cámara calma room-snapped, arena lateral JRPG y minimapa. |
| `shaders.lua` / `lighting_pipeline.lua` | Compilación GLSL con `safeSend`/`hasUniform`, MRT Deferred 2D, 2D GI, Dual-Kawase Bloom, ACES, fallback `lit`+`post` y telemetría `[PERF]`. |
| `beat_sync.lua` | PLL sin deriva acoplado a `audio:getTrackState()`, groove idle del Pudú/rivales y rebote elástico del sombrero café. |
| `spell_ritual.lua` | Ritual de flechas luminosas convexas (2 primitivas por flecha) que suma `+8%` de poder al ritmo del jugador mientras responde la IA. |
| `battle_fx.lua` / `battle_hud.lua` | Invocaciones, VFX, textos flotantes zero-overlap, combos, strip inferior Final Fantasy de `78px` y barra diegética rival. |
| `director_panel.lua` | Herramienta Director `[F2]`. |
| `battle_worker.lua` / `sprite_worker.lua` / `ai_bridge.py` | Hilos HTTP hacia `127.0.0.1:18425`, juez offline de 0 ms con paridad exacta de 34 campos JSON y generación/caché de sprites en vivo. |

---

## 3. Reglas Inquebrantables de Ingeniería

Cualquier PR, commit o subagente que viole una de estas 10 reglas debe corregirse antes de integrar:

### R1. LÖVE2D 11.5 estricto y soporte dual Fused / Unfused
- `conf.lua` fija `t.version = "11.5"`, `1280×720`, `t.window.msaa = 0`, `t.window.highdpi = false`.
- Todos los sprites pixel-art y normal maps usan `img:setFilter("nearest", "nearest")`. Solo `light_radial.png` y canvases HDR/post usan `"linear"`.
- Toda carga de sprites (`AssetLoader.loadImageRaw`) y persistencia (`stage_overrides.json`) debe soportar tanto ejecución desde carpeta como ejecutable fusionado (`love.filesystem.isFused()`), priorizando carpeta externa (`AssetLoader.getExternalBaseDir()` / `getSourceBaseDirectory()`) para que `[F5]` y `assets/custom/` funcionen incluso dentro del `.exe`.

### R2. CERO Unicode tofu (`[X]` / `□`) en fuentes
- La fuente empaquetada `assets/fonts/PTSans.ttc` soporta ASCII + español completo (`á é í ó ú ü ñ Á É Í Ó Ú Ü Ñ ¡ ¿ ...`).
- **PROHIBIDO** renderizar con `love.graphics.print` / `printf` emojis (`🔥 ⚡ 💀 🎵 🏆`), dingbats (`★ ✓ ✗ ⚠ •`) ni flechas Unicode (`↑ ↓ ← → ↗ ↘`) que la fuente no contenga.
- Todo ícono visual (nota musical, flechas del ritual, insignias, estrellitas, exclamación `!`) debe dibujarse con **primitivas geométricas de LÖVE2D** (`rectangle`, `ellipse`, `polygon`, `line`).
- Al truncar texto con `...`, retroceder siempre por límites válidos de **codepoint UTF-8** (nunca cortar a la mitad un carácter acentuado de 2 bytes).

### R3. Flechas del ritual construidas con 2 polígonos convexos
- LÖVE2D exige que `love.graphics.polygon("fill", ...)` reciba polígonos **convexos**; un polígono cóncavo de 7 vértices en forma de flecha produce artefactos/triángulos invertidos.
- En `spell_ritual.lua`, cada flecha direccional (`up`, `down`, `left`, `right`) **SIEMPRE** se dibuja rotando el canvas y trazando **2 primitivas convexas separadas**:
  1. Tallo rectangular convexo (`rectangle("fill", ...)`).
  2. Cabeza triangular convexa (`polygon("fill", x1,y1, x2,y2, x3,y3)`).
  3. Más un respaldo inflado oscuro detrás con la misma técnica de 2 partes para contraste nítido.

### R4. `safeSend` / `hasUniform` obligatorio en GLSL + Fallback seguro
- Los compiladores GLSL eliminan uniformes no usados; llamar `shader:send(name, val)` directo crashea LÖVE2D si el uniforme fue optimizado.
- **PROHIBIDO** llamar `sh:send(...)` sin verificar antes `sh:hasUniform(uniform)` (idealmente vía `Shaders.send(shaderSet, shaderName, uniform, ...)` con caché `_uniformCache`).
- Toda característica avanzada (MRT de 4 targets `multicanvas >= 4`, `rgba16f`, Radiance Cascades 2D GI, Dual-Kawase Bloom) debe degradar limpiamente al shader `lit` + `post` si la GPU del usuario no la soporta.
- Control de halo/bloom: usar `emissiveSelective` y ponderación de Karis + tone mapping ACES para evitar halos blancos quemados sobre sprites y texto.

### R5. Escapar `%-%-` en flags CLI de Lua y salida limpia en errores
- En patrones Lua (`string.match`), `-` es el cuantificador no-codicioso, **NO** un guion literal.
- Todo flag CLI en `parseCliArgs` **DEBE** escaparse con `%-%-` (ejemplo: `a:match("^%-%-encounter=(%d+)$")`, `a:match("^%-%-auto%-prompt=(.+)$")`, `a:match("^%-%-quit%-after=(%d+%.?%d*)$")`).
- `love.errorhandler` **DEBE** inspeccionar `arg` buscando `^%-%-quit%-after=`: si está presente, imprimir el stack trace completo en `io.stderr`, hacer `io.stderr:flush()` y ejecutar `os.exit(1)` inmediatamente para que ningún test automatizado quede congelado en la pantalla azul de error.

### R6. Carriles visuales Zero-Overlap (`1280×720`)
Ningún elemento de UI o texto de combate puede pisar a otro. Respetar estrictamente estos carriles:

| Carril / Elemento | Zona reservada (`1280×720`) | Regla anti-solapamiento |
|---|---|---|
| **Barra superior HUD** | `y = 10..48` | Izquierda: 1 chip de contexto (Bioma o Rival). Derecha: controles compactos (`Música`, `Mapa/Huir`, `Director [F2]`). |
| **Toast / Narración superior** | Centro `y = 12..46` | Auto-ajustado; **oculto durante fase `ritual`**. |
| **Píldora de estado del Ritual** | Centro `y >= 56` | Siempre `>= 42px` encima de la bandeja de flechas (`panelY >= 126`). |
| **Bandeja de Flechas del Ritual** | Centro `barY = max(minBarY, h * 0.235)` | Barra de poder debajo (`panelY + panelH + 8`). |
| **Globo de Anticipación del Rival** | `x >= w * 0.58`, `y = enemyY - 216` | Exclusivo sobre el rival durante `ritual`; jamás cruza al centro sobre las flechas. |
| **Anclas de Arena de Batalla** | Pudú `(0.28w, 0.65h)` · Rival `(0.72w, 0.65h)` | Separación clara de vista lateral JRPG; sombrero del Pudú anclado a cabeza por dirección (`HAT_HEAD_OFFSETS`). |
| **Barra HP + Estados del Rival** | Debajo de `(enemyX, enemyY)` | Barra diegética + píldoras de estado (`MOJADO`, `CONGELADO`, etc.) lado a lado sin tapar el sprite. |
| **Textos flotantes (`¡CRÍTICO!`)** | Clamped `[130..w-135, 76..h-130]` | Staggering anti-overlap de 6 pasadas en `battleFX:spawnFloatingText`. |
| **Strip inferior Final Fantasy** | Fondo `h - 86 .. h - 8` (`78px` alto) | Izquierda: retrato + HP Pudú. Derecha: caja pura de prompt. |

### R7. Cámara calma Room-Snapped en el mapa diagonal `↗`
- El Overworld asciende en diagonal de abajo-izquierda hacia arriba-derecha (`↗`, `u = 0..118`) a través de 4 biomas (`desierto` -> `costa` -> `montana` -> `chiloe`), con un combate obligatorio por bioma.
- La cámara en exploración permanece **100% QUIETA** dentro de la habitación activa (cero seguimiento nervioso frame a frame que provoque mareo).
- Solo dispara **un único paneo suave (`smoothstep`)** cuando el Pudú cruza el umbral del cuarto (`du > 7.4` o `dv > 5.4`), bloqueando brevemente el avance durante el paneo.

### R8. Baile idle al compás SIN notas ni mecánica rítmica punitiva
- `beat_sync.lua` se acopla al reloj real de audio (`source:tell("seconds")`, `bpm` y `beatOffset`) mediante un PLL sin deriva.
- El compás mueve exclusivamente el baile **idle** alegre estilo *Superstar Saga* del Pudú, el rebote elástico de su sombrero puntiagudo café y el groove de los rivales.
- **PROHIBIDO** agregar notas musicales flotando/cayendo tipo *Guitar Hero*, ventanas de precisión punitivas, mecánica rítmica obligatoria o botón "Bailar" en el HUD. El ritual de flechas otorga `+8%` de poder por flecha al ritmo cómodo del jugador.

### R9. Cero chips de pistas de prompts
- **PROHIBIDO** renderizar chips clickeables con soluciones o ejemplos de prompts en el HUD de batalla (arruinan la magia creativa del juego).
- Única ayuda permitida: **Regla de 2 fallos (`nonCritMissCount >= 2`)**, donde el rival pronuncia en su globo diegético su `semiHintLine` sutil y sin spoilers al volver al turno del jugador.

### R10. Sincronía obligatoria de empaquetado `.exe`
- Cada vez que se cree un archivo `.lua` nuevo en la raíz requerido por el juego (incluyendo `asset_loader.lua` y `json.lua`), **DEBE** agregarse inmediatamente a `LUA_FILES` en `tools/build_windows_exe.py`.

---

## 4. Matriz de Propiedad de Archivos para Subagentes en Paralelo

Para evitar conflictos de merge cuando trabajen varios subagentes en paralelo, cada archivo tiene **un único propietario activo por fase**:

| Rol del Subagente | Archivos de Propiedad Exclusiva | Solo Lectura / Requiere Handoff |
|---|---|---|
| **Integrador / Lead (Coordinador)** | `main.lua`, `conf.lua`, `json.lua`, `run.sh`, `run_windows.ps1`, `Jugar_Windows.bat` | Todos los demás módulos |
| **World & HD-2D Render Specialist** | `stage_renderer.lua`, `shaders.lua`, `lighting_pipeline.lua` | `encounters.lua`, `asset_loader.lua`, `main.lua` |
| **Encounters & Content Designer** | `encounters.lua` | `stage_renderer.lua`, `ai_bridge.py` |
| **Combat VFX & Ritual Specialist** | `battle_fx.lua`, `spell_ritual.lua` | `audio.lua`, `beat_sync.lua`, `main.lua` |
| **Audio & Groove Specialist** | `audio.lua`, `beat_sync.lua`, `tools/generate_battle_music.py`, `tools/generate_lyria3_music.py` | `main.lua` |
| **AI Bridge & Offline Judge Specialist** | `ai_bridge.py`, `battle_worker.lua`, `sprite_worker.lua`, `requirements.txt`, `.env.example` | `encounters.lua`, `json.lua`, `tools/sprite_studio.py` |
| **UI / HUD & Tools Specialist** | `battle_hud.lua`, `director_panel.lua` | `main.lua`, `encounters.lua` |
| **Sprite & Asset Pipeline Specialist** | `asset_loader.lua`, `tools/sprite_studio.py`, `tools/generate_encounter_sprites.py`, `tools/generate_popular_gags.py`, `assets/` | `encounters.lua` |
| **QA & Release Build Engineer** | `tools/build_windows_exe.py`, `screenshots/`, `dist/` | Todos los `.lua` y `.py` |

**Regla de coordinación:** Si un subagente necesita un nuevo callback, campo o hook en `main.lua`, lo documenta en su reporte final (firma exacta + punto de integración) y **el Integrador** aplica el cableado en `main.lua`. En fases específicas (como Fase 00), el Coordinador puede delegar archivos de infraestructura a un subagente dedicado manteniendo siempre la regla de 1 propietario exclusivo por archivo.

---

## 5. Contrato JSON (34 Campos) y Contrato CLI Obligatorio

### 5.1 Contrato HTTP del Puente IA (`127.0.0.1:18425`)

- `GET /health` -> `{ "ok": true, "provider": "...", "model": "gemini-2.5-flash", "token_ready": true|false }`
- `POST /sprite` -> entrada `{ "name", "sprite_prompt", "keep_purple", "target_dim" }` -> salida `{ "ok": true, "diff_b64": "...", "norm_b64": "...", "cached": true|false }`
- `POST /battle_prompt` -> entrada `{ "encounter_id", "prompt", "turn", "stage_states", "active_props", "enemy_hp", "pudu_hp", "mock" }`

**Esquema obligatorio de respuesta (34 campos exactos, tanto online en `ai_bridge.py` como offline en `battle_worker.lua`):**

| Grupo | Campos obligatorios y tipos/valores válidos |
|---|---|
| **Admisión y nombre** | `approved` (bool), `reject_reason` (string), `summon_name` (string) |
| **Sprite** | `sprite_mode` (`"generate_live"` \| `"existing"`), `existing_sprite` (`"none"` o uno de los 27 sprites válidos: 14 gags + props + fauna), `sprite_prompt` (string), `keep_purple` (bool) |
| **Presentación VFX/SFX** | `delivery_style`, `particle_fx`, `sfx`, `reaction_sfx`, `ritual_theme_color` (hex `#RRGGBB`) |
| **Resolución de combate** | `outcome_type`, `is_critical` (bool), `damage_to_enemy` (number), `damage_to_pudu` (number), `heal_pudu` (number) |
| **Reacciones y comedia** | `enemy_reaction` (`idle`, `crying`, `laughing`, `angry`, `wet`, `frozen`, `shocked`, `dizzy`, `scared`, `happy`, `embarrassed`, `chased`, `sleeping`, `charmed`, `defeated`), `pudu_reaction`, `enemy_speech`, `narrator_text`, `comedy_score` (int), `comedy_badge` (string), `status_tag` (string) |
| **Contraataque enemigo** | `enemy_counter_name`, `enemy_counter_line`, `enemy_counter_damage` (number), `enemy_counter_fx` |
| **Persistencia y Combos 2 Turnos** | `keep_prop_on_stage` (bool), `prop_anchor`, `adds_stage_state` (`"none"`, `"mojado"`, `"congelado"`, `"aceitoso"`, `"enjabonado"`, `"oscuro"`, `"ruidoso"`, `"caliente"`, `"pegajoso"`), `combo_triggered` (`"none"`, `"combo_electro"`, `"combo_deep_freeze"`, `"combo_steam_sauna"`, `"combo_slip_slide"`, `"combo_fire_boom"`, `"combo_chaos"`), `combo_name` (string), `anticipation_line` (string) |

**Invariante de rechazo (`approved == false`):** `is_critical = false`, `damage_to_enemy = 0`, `damage_to_pudu = 0`, `heal_pudu = 0`, `adds_stage_state = "none"`, `combo_triggered = "none"`, `combo_name = ""`, `anticipation_line = ""`.

### 5.2 Contrato CLI Obligatorio (debe mantenerse operativo en TODA fase/PR)

Todo PR debe preservar estos flags en `main.lua` (`parseCliArgs` con patrones `%-%-`):

| Flag CLI | Propósito QA / Automatización |
|---|---|
| `--mode=explore\|battle` | Inicia directo en Overworld `↗` o en Arena de Batalla. |
| `--biome=desierto\|costa\|montana\|chiloe` | Teleporta al bioma indicado en modo exploración. `montaña` apunta a `montana`. `bosque` y `ciudad` apuntan a `chiloe`. |
| `--encounter=1..9` | Selecciona uno de los 4 combates de campaña o uno de los combates de QA (5 al 9). |
| `--mock` | Activa modo prueba 0 ms (sin llamadas externas a Gemini). |
| `--auto-prompt="<texto>"` | Envía el prompt automáticamente y resuelve las flechas del ritual en modo test. |
| `--test-ritual` | Abre el ritual de flechas luminosas de inmediato para inspección visual. |
| `--demo-combo=<id_combo>` | Dispara el espectáculo VFX + banner + daño crítico de un Super-Combo. |
| `--force-reaction=<reacción>` | Fuerza una de las reacciones animadas del rival. |
| `--lighting=dia\|atardecer\|noche\|teatral` | Fija preset de iluminación HD-2D. |
| `--transition-preview=0.0..1.0` | Congela la cortinilla JRPG en el progreso indicado para captura. |
| `--battle-enter-preview` | Captura la animación de entrada corriendo a la arena. |
| `--open-director` | Abre el Panel Director `[F2]` al inicio. |
| `--disable-gi` / `--disable-bloom` | Permite medir rendimiento y validar degradación limpia. |
| `--print-perf` | Imprime la línea `[PERF] fps=... deferred=... gi=... bloom=... drawcalls=...` al salir. |
| `--screenshot=<ruta.png>` | Guarda captura PNG limpia `0.35s` antes de cerrar. |
| `--quit-after=<segundos>` | Cierra limpiamente (`exit 0`) tras N segundos (o `exit 1` si ocurre un error Lua). |

---

## 6. Protocolo de Verificación antes de Reportar una Tarea como Lista

Ningún agente puede dar una tarea por terminada sin completar estos 5 controles objetivos:

1. **Compilación y sintaxis sin errores:**
   - Shell: `bash -n run.sh` si se modificó el lanzador.
   - Python: `python3 -m py_compile ai_bridge.py tools/*.py` (solo los modificados).
   - Lua: arrancar LÖVE2D con `--quit-after=1.8 --print-perf` y comprobar **`exit code == 0`** y ausencia total de `[PUDU FANTASY ERROR]` en `stderr`.
2. **Validación de shaders y rendimiento:**
   - Cero warnings no vacíos en `Shaders.getWarnings(shaders)`.
   - Cero llamadas `shader:send(...)` sin guarda `hasUniform`.
   - FPS estables en la línea `[PERF]`.
3. **Evidencia visual en `1280×720`:**
   - Si el cambio toca UI, shaders, sprites, cámara, ritual o VFX, generar al menos 1 captura con `--screenshot=screenshots/...` y pasarla a **Astra** (o revisarla) confirmando: cero overlap, cero tofu `[X]`, cero flechas rotas y cero halo quemado.
4. **Paridad Online / Offline:**
   - Si se modifica un rival, un estado de escenario, un combo o el contrato JSON en `ai_bridge.py`, reflejar el cambio exactamente en `battle_worker.lua` (motor offline) y probar con un puerto cerrado (`PUDU_BATTLE_PORT=19999`).
5. **Empaquetado íntegro:**
   - Confirmar que cualquier nuevo `.lua` está registrado en `LUA_FILES` dentro de `tools/build_windows_exe.py` y que no se dejaron archivos temporales ni claves `.env` en el repositorio.
