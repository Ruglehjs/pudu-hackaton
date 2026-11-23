# AGENTS.md — Pudú Fantasy (Plantilla Lista para Raíz del Repositorio)

> **Cómo usar esta plantilla:** Copia este archivo como `AGENTS.md` en la **raíz del repositorio nuevo** antes de escribir la primera línea de código con **Codex** y sus subagentes. Todas las reglas, contratos y protocolos aquí definidos son vinculantes para cualquier agente que modifique el proyecto.

---

## 1. Identidad del Proyecto y Arquitectura de Carpetas

**Nombre:** **Pudú Fantasy — Batallas de Prompts al Compás**  
**Género:** RPG humorístico HD-2D por turnos (inspirado en *Final Fantasy* + expresividad rítmica idle de *Mario & Luigi: Superstar Saga*) donde el jugador vence a 9 rivales cómicos escribiendo **cualquier prompt libre**.  
**Motor y Stack:**
- **Cliente de juego:** **LÖVE2D 11.5** (LuaJIT, `1280×720` base, compilable a `.love` y `.exe` Win64 portable).
- **Puente IA opcional (local):** **Python 3.10+** (`ai_bridge.py` en `http://127.0.0.1:18425`, compatible con **Vertex AI ADC** y **Gemini API Key**):
  - Etapa 1 (Juicio cómico rápido): `gemini-2.5-flash` con `thinkingBudget=0`, TLS persistente y `responseSchema` estricto de **34 campos JSON**.
  - Etapa 2 (Sprite HD-2D en vivo, lanzamiento paralelo especulativo): `gemini-2.5-flash-image` + recorte alfa + mapa de normales Sobel (`_n.png`).
- **Modo 100% Offline / Standalone:** `battle_worker.lua` incluye un motor de respaldo completo en Lua puro (los 9 encuentros + 6 Super-Combos de 2 turnos + sanitizador anti-trampas) que responde en **0 ms** cuando no hay puente Python ni WiFi.

### Estructura de carpetas del repositorio

```text
pudu-fantasy/
├── AGENTS.md                       # Este documento (ley del repositorio)
├── conf.lua                        # Configuración LÖVE2D 11.5 (1280x720, msaa=0, highdpi=false)
├── main.lua                        # Integrador principal: ciclo love.*, máquina de estados, CLI, workers
├── json.lua                        # Codificador/decodificador JSON puro en Lua
├── encounters.lua                  # 4 biomas (↗), 9 rivales, temas de escenario, semiHintLine, overrides I/O
├── stage_renderer.lua              # Mapa diagonal ↗, relieve 3D, cámara calma room-snapped, arena batalla, minimapa
├── shaders.lua                     # Shaders GLSL (MRT G-Buffer, JFA SDF, 5-Cascade Radiance GI, Dual-Kawase Bloom, ACES, fallback)
├── lighting_pipeline.lua           # Orquestador GPU Deferred 2D + 2D GI + HDR Bloom + estadísticas [PERF]
├── audio.lua                       # Música con metadata exacta (BPM, beats, beatOffset) y catálogo SFX
├── beat_sync.lua                   # PLL sin deriva sobre source:tell("seconds") + baile Pudú + física del sombrero
├── spell_ritual.lua                # Minijuego de flechas luminosas convexas (carga de poder mientras responde la IA)
├── battle_fx.lua                   # Invocaciones, partículas, burbujas, textos flotantes zero-overlap, combos y finales cómicos
├── battle_hud.lua                  # HUD minimalista estilo Final Fantasy (strip 78px, barra rival diegética, cero spoilers)
├── director_panel.lua              # Panel Director [F2] para artistas/QA (biomas, reacciones, luz, escala, combos)
├── victory_album.lua               # Modal "Álbum de Locuras" [J] en grilla 3x3 con persistencia victory_album.json
├── battle_worker.lua               # Hilo LÖVE2D HTTP hacia /battle_prompt + fallback offline completo
├── sprite_worker.lua               # Hilo LÖVE2D HTTP hacia /sprite (decodificación base64 -> Image + normal map)
├── ai_bridge.py                    # Servidor HTTP local 127.0.0.1:18425 (Vertex AI / Gemini API + caché RAM/disco)
├── run.sh                          # Lanzador macOS/Linux (levanta puente + LÖVE2D + cleanup trap)
├── run_windows.ps1 / Jugar_Windows.bat
├── requirements.txt / .env.example
├── assets/
│   ├── fonts/PTSans.ttc            # Fuente empaquetada obligatoria
│   ├── audio/                      # battle_user_main.wav + pistas *_lyria.ogg + SFX *.wav
│   ├── tiles/                      # 5 suelos (*.png + *_n.png)
│   ├── sprites/                    # pudu_8dir_sheet, pudu_hero, light_radial, props, encounters/, gags/
│   ├── ui/portraits/               # pudu_happy.png, pudu_shocked.png, pudu_angry.png
│   └── custom/                     # Drop-in de artistas con recarga en vivo [F5]
├── tools/
│   ├── sprite_studio.py            # Limpieza magenta, normal map Sobel (generate_normal_map), previews
│   ├── build_windows_exe.py        # Empaquetador PuduFantasy.love + PuduFantasy.exe + PuduFantasy-Windows-x64.zip
│   └── love-win64/                 # Binarios LÖVE2D 11.5 Win64 (love.exe + 7 DLLs)
├── cache/sprites/                  # Caché persistente de sprites generados en vivo (no versionar pesados)
├── screenshots/                    # Capturas [F12] y batería QA CLI
└── dist/                           # Artefactos de entrega (.love, PuduFantasy-Windows/, .zip)
```

---

## 2. Reglas Inquebrantables de Ingeniería

Cualquier PR, commit o subagente que viole una de estas reglas debe corregirse antes de integrar:

### R1. LÖVE2D 11.5 estricto y soporte dual Fused / Unfused
- `conf.lua` fija `t.version = "11.5"`, `1280×720`, `t.window.msaa = 0`, `t.window.highdpi = false`.
- Todos los sprites pixel-art y normal maps usan `img:setFilter("nearest", "nearest")`. Solo `light_radial.png` y canvases HDR/post usan `"linear"`.
- Toda carga de sprites (`loadImageRaw`) y persistencia (`victory_album.json`, `stage_overrides.json`) debe soportar tanto ejecución desde carpeta como ejecutable fusionado (`love.filesystem.isFused()`), priorizando carpeta externa (`getSourceBaseDirectory()`) para que `[F5]` y `assets/custom/` funcionen incluso dentro del `.exe`.

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
- Todo flag CLI en `parseCliArgs` **DEBE** escaparse con `%-%-` (ejemplo: `a:match("^%-%-encounter=(%d+)$")`, `a:match("^%-%-auto%-prompt=(.+)$")`).
- `love.errorhandler` **DEBE** inspeccionar `arg` buscando `^%-%-quit%-after=`: si está presente, imprimir el stack trace en `stderr` y ejecutar `os.exit(1)` inmediatamente para que ningún test automatizado quede congelado en la pantalla azul de error.

### R6. Carriles visuales Zero-Overlap (`1280×720`)
Ningún elemento de UI o texto de combate puede pisar a otro. Respetar estrictamente estos carriles:

| Carril / Elemento | Zona reservada (`1280×720`) | Regla anti-solapamiento |
|---|---|---|
| **Barra superior HUD** | `y = 10..48` | Izquierda: 1 chip de contexto (Bioma o Rival). Derecha: controles compactos (`Música`, `Álbum [J]`, `Mapa/Huir`, `Director [F2]`). |
| **Toast / Narración superior** | Centro `y = 12..46` | Auto-ajustado; **oculto durante fase `ritual`**. |
| **Píldora de estado del Ritual** | Centro `y >= 56` | Siempre `>= 42px` encima de la bandeja de flechas (`panelY >= 126`). |
| **Bandeja de Flechas del Ritual** | Centro `barY = max(minBarY, h * 0.235)` | Barra de poder debajo (`panelY + panelH + 8`). |
| **Globo de Anticipación del Rival** | `x >= w * 0.58`, `y = enemyY - 216` | Exclusivo sobre el rival durante `ritual`; jamás cruza al centro sobre las flechas. |
| **Anclas de Arena de Batalla** | Pudú `(0.28w, 0.65h)` · Rival `(0.72w, 0.65h)` | Separación clara de vista lateral JRPG; sombrero del Pudú anclado a cabeza por dirección (`HAT_HEAD_OFFSETS`). |
| **Barra HP + Estados del Rival** | Debajo de `(enemyX, enemyY)` | Barra diegética + píldoras de estado (`MOJADO`, `CONGELADO`, etc.) lado a lado sin tapar el sprite. |
| **Textos flotantes (`¡CRÍTICO!`)** | Clamped `[130..w-135, 76..h-130]` | Staggering anti-overlap de 6 pasadas en `battleFX:spawnFloatingText`. |
| **Strip inferior Final Fantasy** | Fondo `h - 86 .. h - 8` (`78px` alto) | Izquierda: retrato + HP Pudú. Derecha: caja pura de prompt. |

### R7. Cámara calma Room-Snapped en el mapa diagonal `↗`
- El Overworld asciende en diagonal de abajo-izquierda hacia arriba-derecha (`↗`, `u = 0..118`) a través de 4 biomas (`bosque` -> `desierto` -> `costa` -> `ciudad`).
- La cámara en exploración permanece **100% QUIETA** dentro de la habitación activa (cero seguimiento nervioso frame a frame que provoque mareo).
- Solo dispara **un único paneo suave (`smoothstep`)** cuando el Pudú cruza el umbral del cuarto (`du > 7.4` o `dv > 5.4`), bloqueando brevemente el avance durante el paneo.

### R8. Baile idle al compás SIN notas ni mecánica rítmica punitiva
- `beat_sync.lua` se acopla al reloj real de audio (`source:tell("seconds")`, `bpm` y `beatOffset`) mediante un PLL sin deriva.
- El compás mueve el baile alegre estilo *Superstar Saga* del Pudú, el rebote elástico de su sombrero puntiagudo café y el groove de los rivales.
- **PROHIBIDO** agregar notas cayendo tipo *Guitar Hero*, ventanas de precisión punitivas o botón "Bailar" en el HUD. El ritual de flechas otorga `+8%` de poder por flecha al ritmo cómodo del jugador.

### R9. Cero chips de pistas de prompts
- **PROHIBIDO** renderizar chips clickeables con soluciones o ejemplos de prompts en el HUD de batalla (arruinan la magia creativa del juego).
- Única ayuda permitida: **Regla de 2 fallos (`nonCritMissCount >= 2`)**, donde el rival pronuncia en su globo diegético su `semiHintLine` sutil y sin spoilers al volver al turno del jugador.

### R10. Sincronía obligatoria de empaquetado `.exe`
- Cada vez que se cree un archivo `.lua` nuevo en la raíz requerido por el juego, **DEBE** agregarse inmediatamente a `LUA_FILES` en `tools/build_windows_exe.py`.

---

## 3. Matriz de Propiedad de Archivos para Subagentes en Paralelo

Para evitar conflictos de merge cuando trabajen varios subagentes en paralelo, cada archivo tiene **un único propietario activo por fase**:

| Rol del Subagente | Archivos de Propiedad Exclusiva | Solo Lectura / Requiere Handoff |
|---|---|---|
| **Integrador / Lead (Codex Principal)** | `main.lua`, `conf.lua`, `run.sh`, `run_windows.ps1`, `Jugar_Windows.bat` | Todos los demás módulos |
| **World & HD-2D Render Specialist** | `stage_renderer.lua`, `shaders.lua`, `lighting_pipeline.lua` | `encounters.lua`, `main.lua` |
| **Encounters & Content Designer** | `encounters.lua` | `stage_renderer.lua`, `ai_bridge.py` |
| **Combat VFX & Ritual Specialist** | `battle_fx.lua`, `spell_ritual.lua` | `audio.lua`, `beat_sync.lua`, `main.lua` |
| **Audio & Groove Specialist** | `audio.lua`, `beat_sync.lua`, `tools/generate_battle_music.py`, `tools/generate_lyria3_music.py` | `main.lua` |
| **AI Bridge & Offline Judge Specialist** | `ai_bridge.py`, `battle_worker.lua`, `sprite_worker.lua`, `requirements.txt`, `.env.example` | `encounters.lua`, `tools/sprite_studio.py` |
| **UI / HUD & Tools Specialist** | `battle_hud.lua`, `director_panel.lua`, `victory_album.lua` | `main.lua`, `encounters.lua` |
| **Sprite & Asset Pipeline Specialist** | `tools/sprite_studio.py`, `tools/generate_encounter_sprites.py`, `tools/generate_popular_gags.py`, `assets/` | `encounters.lua` |
| **QA & Release Build Engineer** | `tools/build_windows_exe.py`, `screenshots/`, `dist/` | Todos los `.lua` y `.py` |

**Regla de coordinación:** Si un subagente necesita un nuevo callback, campo o hook en `main.lua`, lo documenta en su reporte final (firma exacta + línea sugerida) y **el Integrador** aplica el cableado en `main.lua`.

---

## 4. Contrato JSON (34 Campos) y Contrato CLI Obligatorio

### 4.1 Contrato HTTP del Puente IA (`127.0.0.1:18425`)

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

### 4.2 Contrato CLI Obligatorio (debe mantenerse operativo en TODA fase/PR)

Todo PR debe preservar estos flags en `main.lua` (`parseCliArgs` con patrones `%-%-`):

| Flag CLI | Propósito QA / Automatización |
|---|---|
| `--mode=explore\|battle` | Inicia directo en Overworld `↗` o en Arena de Batalla. |
| `--biome=bosque\|desierto\|costa\|ciudad` | Teleporta al bioma indicado en modo exploración. |
| `--encounter=1..9` | Selecciona el encuentro (1 al 9). |
| `--mock` | Activa modo prueba 0 ms (sin llamadas externas a Gemini). |
| `--auto-prompt="<texto>"` | Envía el prompt automáticamente y resuelve las flechas del ritual en modo test. |
| `--test-ritual` | Abre el ritual de flechas luminosas de inmediato para inspección visual. |
| `--demo-combo=<id_combo>` | Dispara el espectáculo VFX + banner + daño crítico de un Super-Combo. |
| `--force-reaction=<reacción>` | Fuerza una de las reacciones animadas del rival. |
| `--lighting=dia\|atardecer\|noche\|teatral` | Fija preset de iluminación HD-2D. |
| `--transition-preview=0.0..1.0` | Congela la cortinilla JRPG en el progreso indicado para captura. |
| `--battle-enter-preview` | Captura la animación de entrada corriendo a la arena. |
| `--open-director` / `--open-album` | Abre el Panel Director `[F2]` o el Álbum de Locuras `[J]` al inicio. |
| `--disable-gi` / `--disable-bloom` | Permite medir rendimiento y validar degradación limpia. |
| `--print-perf` | Imprime la línea `[PERF] fps=... deferred=... gi=... bloom=... drawcalls=...` al salir. |
| `--screenshot=<ruta.png>` | Guarda captura PNG limpia `0.35s` antes de cerrar. |
| `--quit-after=<segundos>` | Cierra limpiamente (`exit 0`) tras N segundos (o `exit 1` si ocurre un error Lua). |

---

## 5. Protocolo de Verificación antes de Reportar una Tarea como Lista

Ningún agente puede dar una tarea por terminada sin completar estos 5 controles objetivos:

1. **Compilación y sintaxis sin errores:**
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
