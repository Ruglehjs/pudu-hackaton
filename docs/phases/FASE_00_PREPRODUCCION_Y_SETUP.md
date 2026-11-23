# Fase 0 — Pre-Producción, Arquitectura Base, `AGENTS.md`, Harness CLI y Estrategia de Assets

| Campo | Detalle |
| :--- | :--- |
| **Fase** | `Fase 00` — Pre-Producción y Cimientos Técnicos |
| **Duración estimada en hackathon** | `45 – 75 min` (bloque inicial antes de escribir gameplay) |
| **Prerrequisitos (Gate de entrada)** | • LÖVE2D **11.5** instalado (`love.app` en `/Applications/` o `tools/love.app` o `love` en `$PATH`)<br>• Git inicializado en el repo nuevo del proyecto<br>• Decisión rápida del equipo: **Modo A** (assets ya listos) o **Modo B** (greybox primero, arte después)<br>• Acceso a **Codex** (implementación con subagentes) y **Astra** (dirección creativa / auditoría visual) |
| **Entregables concretos** | 1. Estructura de carpetas del proyecto (`assets/`, `screenshots/`, `tools/`) y `.gitignore`<br>2. `AGENTS.md` con contratos de módulos, reglas de diseño y convenciones de Lua/LÖVE2D<br>3. `conf.lua` (LÖVE2D `11.5`, `1280x720`, pixel-art crisp sin MSAA)<br>4. `run.sh` ejecutable que detecta LÖVE2D y reenvía todas las banderas CLI (`"$@"`)<br>5. `json.lua` (encoder/decoder UTF-8 ligero para LuaJIT)<br>6. `asset_loader.lua` con carga segura de pares `diff` + `_n` normal map, **fallback automático a greybox procedural** y hot-reload `[F5]`<br>7. `audio.lua` (esqueleto operativo con catálogo de BPM reales y degradación silenciosa si faltan archivos)<br>8. `main.lua` mínimo con `love.errorhandler` a `stderr`, parser CLI seguro (`%-%-`) y captura automática `--screenshot` + `--quit-after` |

---

## 1. Objetivo de Producción y Alcance (Qué SÍ y Qué NO hacer en esta fase)

El objetivo de la Fase 0 es construir una **pista de aterrizaje blindada** para que Codex, sus subagentes y los artistas/músicos del equipo puedan trabajar en paralelo durante toda la hackathon sin pisarse archivos, sin romper el arranque por un PNG o WAV faltante y con verificación automatizada por CLI desde el minuto 1.

### Qué SÍ hacer en Fase 0
- Congelar los contratos de archivos, nombres de módulos y estructura de directorios en `AGENTS.md`.
- Configurar LÖVE2D **11.5** (`conf.lua`) con ventana `1280x720` (`minwidth = 960`, `minheight = 540`, `resizable = true`, `vsync = 1`, `msaa = 0`, `highdpi = false`) y filtro global `nearest`.
- Implementar `love.errorhandler` personalizado que imprima el `debug.traceback` completo a `io.stderr`, haga `flush()` y salga con `os.exit(1)` cuando se ejecuta con `--quit-after=` (evitando que los tests CLI se queden colgados en la pantalla azul de error de LÖVE).
- Implementar el **Harness CLI** en `main.lua` escapando correctamente los guiones en patrones de Lua (`^%-%-mode=(.+)$`, `^%-%-encounter=(%d+)$`, `^%-%-mock`, `^%-%-screenshot=(.+)$`, `^%-%-quit%-after=(%d+%.?%d*)$`, `^%-%-biome=(.+)$`, `^%-%-lighting=(.+)$`).
- Crear `asset_loader.lua` con **Modo Dual (Arte real / Greybox procedural)** y soporte de **recarga en vivo `[F5]`** tanto ejecutando desde carpeta fuente como en builds empaquetados (`isFused`).
- Crear `run.sh` (`chmod +x`) con detección automática de `love.app` y paso limpio de argumentos `"$@"`, dejando el hook listo (opcional/no bloqueante) para el futuro `ai_bridge.py` en puerto `PUDU_BATTLE_PORT:-18425`.
- Verificar que un comando headless/CLI arranque la ventana, dibuje el estado de diagnóstico (o splash greybox), guarde un PNG en `screenshots/fase00_boot.png` y cierre con código `0`.

### Qué NO hacer en Fase 0
- **NO** implementar aún el mapa overworld isométrico ni los 4 biomas (eso es **Fase 1**).
- **NO** escribir shaders GLSL de iluminación ni baile al compás (eso es **Fase 2**).
- **NO** conectar todavía Gemini / Python `ai_bridge.py` ni generar sprites por IA (eso corresponde a la fase de Combate con IA).
- **NO** instalar frameworks externos pesados de ECS o UI; LÖVE2D puro + módulos Lua pequeños y desacoplados ganan en velocidad de hackathon.
- **NO** bloquear el arranque del juego si falta una imagen, una fuente o un archivo de audio.

---

## 2. Modo Assets: ¿Ya tengo sprites/música o los incorporo después?

Pudú Fantasy soporta ambos flujos desde el primer commit gracias a `asset_loader.lua` y `audio.lua`. Elige el modo que mejor refleje el estado de tu equipo hoy:

### Modo A — Ya tengo sprites y música listos desde el minuto 0
Coloca tus archivos directamente en las rutas canónicas antes de ejecutar el primer test:

```text
assets/
├── fonts/
│   └── PTSans.ttc                          # Opcional (fallback a fuente por defecto de LÖVE)
├── audio/
│   ├── battle_user_main.wav                # Canción principal de batalla (139.20 BPM, beatOffset = 0.342s)
│   ├── battle_overworld_lyria.ogg          # Música de exploración (116.04 BPM)
│   ├── battle_superstar_lyria.ogg          # Alternativa batalla (132.01 BPM)
│   ├── battle_boss_lyria.ogg               # Alternativa jefe (141.16 BPM)
│   ├── battle_plaza_lyria.ogg              # Alternativa plaza (120.00 BPM)
│   ├── battle_victory_lyria.ogg            # Fanfarria victoria (136.84 BPM)
│   └── sfx_encounter_start.wav             # Alerta "!" de encuentro JRPG
├── tiles/
│   ├── grass_floor.png       (+ _n.png)    # Normal map opcional con sufijo _n.png
│   ├── stone_floor.png       (+ _n.png)
│   ├── desert_floor.png      (+ _n.png)
│   ├── mountain_floor.png    (+ _n.png)
│   └── coast_floor.png       (+ _n.png)
├── sprites/
│   ├── pudu_8dir_sheet.png   (+ _n.png)    # Grilla 6 cols x 8 rows (filas 0..7 = S, SE, E, NE, N, NW, W, SW)
│   ├── light_radial.png                    # Halo radial suave (filtro linear)
│   ├── gags/
│   │   └── pudu_wizard_hat.png (+ _n.png)  # Sombrero de mago café en punta
│   └── encounters/
│       └── <id_encuentro>.png  (+ _n.png)  # Ej: nino_helado.png, mimo_muro.png, etc.
├── custom/                                 # Sobrescritura rápida de artistas (tiene prioridad sobre sprites/)
└── ui/portraits/
    ├── pudu_happy.png
    ├── pudu_shocked.png
    └── pudu_angry.png
```

- **Convención de Normal Maps**: cada `nombre.png` busca automáticamente `nombre_n.png`. Si existe, se carga en `{ diff = img, norm = normImg }`; si no existe, `norm = nil` y el shader de Fase 2 cae limpiamente a normal plana `(0, 0, 1)`.
- **Iteración en caliente**: los artistas pueden reemplazar cualquier PNG en `assets/` o dejar overrides en `assets/custom/<id>.png` y presionar **`[F5]`** con el juego abierto para ver el cambio al instante.

### Modo B — Arranco SIN arte ni música final (Greybox primero, arte después)
No necesitas copiar ningún PNG ni WAV para avanzar:

1. `asset_loader.lua` detecta los archivos faltantes y genera automáticamente **texturas `ImageData` procedurales en memoria** (con etiqueta de estado `isPlaceholder = true`):
   - **Pudú 6×8**: spritesheet procedural `384x512` (celdas `64x64`) con silueta café de pudú orientada en 8 direcciones, patitas animadas por columna (`0..5`) y contorno legible.
   - **Sombrero de mago**: triángulo café puntiagudo con ala ancha y banda dorada (`64x64`).
   - **Tiles de suelo**: patrones pixel-art `64x64` con `setWrap("repeat", "repeat")` por bioma (`grass_floor`, `stone_floor`, `desert_floor`, `mountain_floor`, `coast_floor`) + normal map plano opcional.
   - **Luz radial (`light_radial`)**: gradiente gaussiano circular procedural `128x128` con filtro `linear`.
   - **Rivales y props**: siluetas procedurales coloreadas con forma reconocible y altura estándar para validar escala y cámara.
2. `audio.lua` registra los metadatos exactos (`user_battle` a `139.20 BPM`, `beatOffset = 0.342s`) y, si el `.wav`/`.ogg` aún no existe, no falla: `getTrackState()` reporta `playing = false` con el BPM real para que el metrónomo interno de `beat_sync.lua` (Fase 2) funcione a la perfección.
3. **Migración a arte final sin tocar código**: en cualquier momento de la hackathon, suelta los `.png` / `.wav` / `.ogg` en las rutas de arriba y presiona `[F5]` (para PNGs) o reinicia el juego (para audio). El greybox desaparece automáticamente donde ya haya archivo real.

---

## 3. División Codex vs Astra + Subagentes de esta Fase

| Agente / Rol | Responsabilidad Exacta | Archivos que Toca (Propiedad Exclusiva) |
| :--- | :--- | :--- |
| **Codex (Coordinador)** | Crea estructura de carpetas, lanza Subagentes A, B y C en paralelo, integra `main.lua` y corre la prueba CLI de arranque + screenshot. | `main.lua`, `.gitignore`, carpetas `assets/*`, `screenshots/` |
| **Subagente A — Repo, Docs & Runner** | Redacta `AGENTS.md` con contratos arquitectónicos inmutables, configura `conf.lua` para LÖVE2D 11.5 y crea `run.sh` ejecutable. | `AGENTS.md`, `conf.lua`, `run.sh` |
| **Subagente B — Asset Loader & Greybox** | Implementa carga segura de imágenes/normal maps (`loadImageRaw`, `loadSpritePair`, `buildQuads`, hot-reload externo/fused) + generadores procedurales greybox para Modo B. | `asset_loader.lua`, `json.lua` |
| **Subagente C — Audio Harness** | Implementa `audio.lua` con tabla `TRACK_META` (`user_battle` a `139.20 BPM`, `beatOffset = 0.342s`, más tracks de overworld/batalla/victoria), carga `"static"` segura, clones SFX y degradación sin crash en Modo B. | `audio.lua` |
| **Astra (Creative / Technical Auditor)** | Revisa `AGENTS.md`, inspecciona el screenshot `fase00_boot.png` y los logs CLI para validar que la arquitectura no tiene deuda técnica ni bloqueos de assets antes de iniciar Fase 1. | Solo lectura + feedback estructurado |

> **Regla anti-conflictos**: Ningún subagente edita `main.lua`. El Coordinador Codex integra las llamadas a `AssetLoader`, `Audio` y `json` dentro de `main.lua` una vez que A, B y C terminan.

---

## 4. Prompt Maestro para Codex (Copiar y Pegar — Orquestación con Subagentes)

```markdown
Eres el Ingeniero Jefe de Pudú Fantasy en LÖVE2D 11.5. Estamos ejecutando la **Fase 0: Pre-Producción, Arquitectura Base, AGENTS.md, Harness CLI y Estrategia de Assets** desde cero en este repositorio.

### Restricciones de Arquitectura
- Motor: LÖVE2D `11.5`, LuaJIT, sin dependencias externas pesadas.
- Resolución base: `1280x720` (`minwidth = 960`, `minheight = 540`, `resizable = true`, `vsync = 1`, `msaa = 0`, `highdpi = false`).
- El juego DEBE arrancar limpiamente tanto si ya hay PNGs/WAVs en `assets/` (**Modo A**) como si la carpeta `assets/` está completamente vacía (**Modo B: fallback automático a greybox procedural**).
- Regla de diseño permanente para `AGENTS.md`: el baile del Pudú en batalla será exclusivamente un baile **idle** expresivo al compás del BPM (estilo Mario & Luigi Superstar Saga), SIN notas musicales flotando, SIN mecánica de ritmo y SIN botón "Bailar".

### Orquestación Obligatoria con Subagentes en Paralelo
Crea las carpetas base (`assets/sprites/encounters`, `assets/sprites/gags`, `assets/tiles`, `assets/audio`, `assets/ui/portraits`, `assets/custom`, `screenshots`) y `.gitignore`, y lanza **3 subagentes en paralelo** respetando propiedad exclusiva de archivos:

1. **Subagente A (`AGENTS.md`, `conf.lua`, `run.sh`)**:
   - `conf.lua`: `t.identity = "pudu_fantasy_battle"`, `t.version = "11.5"`, `t.window.title = "Pudú Fantasy — Batallas de Prompts al Compás"`, `1280x720`, `msaa = 0`, `highdpi = false`, módulos habilitados `audio, data, event, font, graphics, image, keyboard, math, mouse, sound, system, thread, timer, window` y deshabilitados `joystick, physics, touch, video`.
   - `run.sh` (ejecutable `chmod +x`, `set -euo pipefail`): usa `PORT="${PUDU_BATTLE_PORT:-18425}"`, arranca `ai_bridge.py` solo si existe ese archivo y no está respondiendo `/health`, busca `love` en `$DIR/tools/love.app/Contents/MacOS/love`, `/Applications/love.app/Contents/MacOS/love` o `command -v love`, y ejecuta `PUDU_BATTLE_PORT="$PORT" "$LOVE_BIN" "$DIR" "$@"`.
   - `AGENTS.md`: documenta el árbol de archivos, contrato de cada módulo (`encounters.lua`, `stage_renderer.lua`, `shaders.lua`, `beat_sync.lua`, `audio.lua`, `asset_loader.lua`, `json.lua`, `main.lua`), convenciones de assets (Modo A vs Modo B, sufijo `_n.png`, grilla Pudú `6x8`, hot-reload `[F5]`), lista de banderas CLI con recordatorio de escapar `%-%-` en Lua, y reglas no negociables de cámara calma por salas y baile solo idle.

2. **Subagente B (`asset_loader.lua`, `json.lua`)**:
   - `json.lua`: encoder/decoder JSON UTF-8 mínimo y seguro para LuaJIT (`json.encode`, `json.decode`).
   - `asset_loader.lua`: expone `AssetLoader.loadAll(encountersList)`, `AssetLoader.loadImageRaw(path, repeatWrap)`, `AssetLoader.loadSpritePair(basePath, repeatWrap)`, `AssetLoader.buildQuads(img, cols, rows)` y `AssetLoader.getExternalBaseDir()`.
   - Lee archivos desde disco externo (`io.open(..., "rb")` -> `love.filesystem.newFileData`) antes de `love.filesystem.getInfo` para que `[F5]` recargue PNGs en vivo incluso en builds unfused/fused.
   - Si falta un archivo, genera automáticamente placeholders procedurales via `love.image.newImageData` (Pudú `6x8` orientado en 8 direcciones, sombrero café puntiagudo, 5 tiles repetibles `grass_floor`, `stone_floor`, `desert_floor`, `mountain_floor`, `coast_floor`, `light_radial` con filtro linear, y silueta genérica de rival/prop) marcando `pair.isPlaceholder = true` y contando `assets.stats = { realCount, placeholderCount }`.

3. **Subagente C (`audio.lua`)**:
   - Implementa `Audio.new(muted)` con `Audio.TRACK_META`:
     - `user_battle`: `path = "assets/audio/battle_user_main.wav"`, `bpm = 139.20`, `beats = 37`, `beatOffset = 0.342`, `loop = true`
     - `overworld`: `path = "assets/audio/battle_overworld_lyria.ogg"`, `bpm = 116.04`, `beats = 64`, `loop = true`
     - `superstar`: `path = "assets/audio/battle_superstar_lyria.ogg"`, `bpm = 132.01`, `beats = 64`, `loop = true`
     - `boss`: `path = "assets/audio/battle_boss_lyria.ogg"`, `bpm = 141.16`, `beats = 64`, `loop = true`
     - `plaza`: `path = "assets/audio/battle_plaza_lyria.ogg"`, `bpm = 120.00`, `beats = 64`, `loop = true`
     - `victory`: `path = "assets/audio/battle_victory_lyria.ogg"`, `bpm = 136.84`, `beats = 32`, `loop = false`
   - Carga pistas como `"static"` con `pcall` para `source:tell("seconds")` preciso. Si faltan archivos en disco, los registra en `self.missing` sin lanzar error.
   - Expone `playTrack(trackId, restartIfSame)`, `getTrackState()` (retornando `id, trackId, bpm, beatOffset, pos, duration, playing, paused`), `play(sfxId, vol, jitter, pitch)`, `toggleMusic()`, `toggleMute()`, `setTrackPaused(paused)` y `stopAll()`.

### Integración en `main.lua` (Coordinador)
Cuando terminen los 3 subagentes, crea `main.lua`:
- Define `love.errorhandler(msg)` que imprima `debug.traceback` a `io.stderr`, haga `flush()`, y haga `os.exit(1)` si algún argumento coincide con `"^%-%-quit%-after="`.
- Implementa `parseCliArgs(argList)` escapando `%-%-` en todos los patrones Lua:
  - `--mode=(.+)` (`explore` por defecto o `battle`)
  - `--biome=(.+)`
  - `--encounter=(%d+)`
  - `--lighting=(.+)`
  - `--mock`
  - `--screenshot=(.+)`
  - `--quit-after=(%d+%.?%d*)`
- Implementa `saveScreenshotTo(path)` usando `love.graphics.captureScreenshot` (disparada cuando `cliElapsed >= cliQuitAfter - 0.35`).
- Dibuja una pantalla limpia de diagnóstico de Fase 0 mostrando: modo CLI actual, encuentro, flags activos, conteo de assets reales vs greybox (`Modo A` / `Modo B`), muestra visual de los sprites cargados (Pudú, sombrero, tiles de biomas) y estado de `Audio`, además de responder a `[F5]` (hot-reload de sprites) y `[M]` (mute).

### Verificación CLI Obligatoria al Terminar
Ejecuta estos comandos y confirma exit code `0` y archivo PNG generado no vacío:
1. `./run.sh --mode=explore --mock --screenshot=screenshots/fase00_boot.png --quit-after=1.5`
2. `./run.sh --mode=battle --encounter=1 --mock --screenshot=screenshots/fase00_battle_cli.png --quit-after=1.5`
Verifica que no haya errores en `stderr` ni advertencias de sintaxis Lua (`luajit -bl` si está disponible). Reporta el resumen de archivos creados y resultados de pruebas.
```

---

## 5. Prompts Individuales por Subagente (Opcional si el equipo divide tareas)

### Subagente A — `AGENTS.md`, `conf.lua` y `run.sh`
```markdown
Crea únicamente `AGENTS.md`, `conf.lua` y `run.sh` para Pudú Fantasy en LÖVE2D 11.5.
- `conf.lua`: `identity = "pudu_fantasy_battle"`, `version = "11.5"`, ventana `1280x720` (`minwidth=960`, `minheight=540`, `resizable=true`, `vsync=1`, `msaa=0`, `highdpi=false`), desactivar `joystick`, `physics`, `touch`, `video`.
- `run.sh`: ejecutable (`chmod +x`), detecta `tools/love.app`, `/Applications/love.app` o `love` en `$PATH`, define `PUDU_BATTLE_PORT="${PUDU_BATTLE_PORT:-18425}"`, solo intenta levantar `ai_bridge.py` si el archivo existe, y pasa `"$@"` íntegro a LÖVE2D.
- `AGENTS.md`: documenta arquitectura modular, contratos entre fases (0, 1, 2+), rutas de assets (Modo A real vs Modo B greybox + normal maps `_n.png` + `[F5]` hot-reload), escape obligatorio `%-%-` en flags CLI de Lua, cámara calma por salas y prohibición de notas flotantes/mecánica rítmica en el baile idle.
No modifiques `main.lua` ni ningún otro archivo.
```

### Subagente B — `asset_loader.lua` y `json.lua`
```markdown
Crea únicamente `asset_loader.lua` y `json.lua` para Pudú Fantasy (LÖVE2D 11.5 / LuaJIT).
- `json.lua`: encoder/decoder JSON UTF-8 sin dependencias externas.
- `asset_loader.lua`: carga pares `{ diff, norm, isPlaceholder }` buscando primero en disco externo (`getExternalBaseDir()`) para hot-reload `[F5]` y luego en `love.filesystem`, con filtro `nearest` (salvo `light_radial.png` que usa `linear`) y `setWrap("repeat", "repeat")` en tiles.
- Implementa fallbacks procedurales limpios vía `love.image.newImageData` para: `pudu_8dir_sheet` (6 cols x 8 rows), `pudu_wizard_hat`, los 5 tiles (`grass_floor`, `stone_floor`, `desert_floor`, `mountain_floor`, `coast_floor`), `light_radial`, retratos y sprites genéricos de encuentros/props.
- Expone `loadAll(encountersList)`, `loadImageRaw`, `loadSpritePair`, `buildQuads` y `getExternalBaseDir`. No toques `main.lua`.
```

### Subagente C — `audio.lua`
```markdown
Crea únicamente `audio.lua` para Pudú Fantasy en LÖVE2D 11.5.
- Define `Audio.TRACK_META` con `user_battle` (`assets/audio/battle_user_main.wav`, `bpm = 139.20`, `beats = 37`, `beatOffset = 0.342`, `loop = true`), `overworld` (`116.04 BPM`), `superstar` (`132.01 BPM`), `boss` (`141.16 BPM`), `plaza` (`120.00 BPM`) y `victory` (`136.84 BPM`).
- Carga música y SFX como `"static"` protegidos con `pcall` y `love.filesystem.getInfo`. Si faltan archivos (Modo B), guarda las rutas en `self.missing` y nunca crashea.
- Cuando un track existe y el jugador mutea (`toggleMusic`/`toggleMute`), mantén el `Source` corriendo a volumen `0.0` para que `source:tell("seconds")` siga sincronizado con el reloj musical.
- Expone `playTrack`, `getTrackState`, `play`, `setTrackPaused`, `setMusicVolume`, `toggleMusic`, `toggleMute`, `stopAll`. No toques `main.lua`.
```

---

## 6. Prompt para Astra (Design Review & Auditoría Visual de la Fase)

> **Adjunta a Astra**: `screenshots/fase00_boot.png`, `screenshots/fase00_battle_cli.png` y el contenido de `AGENTS.md`.

```markdown
Eres Astra, Directora Técnica y de Arte de Pudú Fantasy. Revisa los entregables de la **Fase 0 (Setup, AGENTS.md, Asset Loader y Harness CLI)** con las capturas adjuntas (`fase00_boot.png` y `fase00_battle_cli.png`).

Audita específicamente:
1. **Legibilidad del pixel-art / greybox**: ¿La ventana se renderiza nítida a `1280x720` con filtro `nearest` sin borrosidad ni artefactos de DPI? Si estamos en Modo B (greybox), ¿son distinguibles visualmente el Pudú, su sombrero café y los 5 tiles de bioma?
2. **Contratos de `AGENTS.md`**: ¿Están claras las fronteras entre archivos para que los subagentes de Fase 1 (Overworld) y Fase 2 (Arena + Baile) trabajen sin pisarse? ¿Falta alguna regla de prevención de bugs (escape `%-%-`, fallback sin assets, prohibición de notas flotantes)?
3. **Harness CLI**: ¿Las dos capturas demuestran que `--mode=explore` y `--mode=battle --encounter=1` parsearon bien sus banderas sin errores?
4. **Veredicto**: Responde con `APROBADO PARA FASE 1` o `BLOQUEADO` + máximo 3 ajustes quirúrgicos antes de pasar a Fase 1.
```

---

## 7. Gate de Iteración en Equipo (Playtest de 5 min + Definition of Done)

### Checklist de Definition of Done (DoD)
- [ ] `./run.sh` abre la ventana de LÖVE2D 11.5 a `1280x720` en menos de 2 segundos sin errores en consola.
- [ ] Con `assets/` vacío (Modo B), el juego arranca con placeholders procedurales legibles y **cero crashes**.
- [ ] Si colocas al menos un PNG real (ej. `assets/sprites/pudu_8dir_sheet.png`) y presionas **`[F5]`**, el sprite cambia en vivo sin reiniciar.
- [ ] Si provocas un error temporal de Lua y ejecutas con `--quit-after=1.0`, el proceso imprime el stacktrace completo en `stderr` y termina inmediatamente con código `1` (no se queda colgado).
- [ ] Las banderas `--mode`, `--encounter`, `--mock`, `--screenshot` y `--quit-after` funcionan correctamente (sin el bug de `-` sin escapar en patrones Lua).
- [ ] `AGENTS.md` está commiteado y todo el equipo sabe si inicia en Modo A o Modo B.

### Comandos Exactos de Verificación
```bash
# 1. Prueba de arranque en modo exploración + captura automática
./run.sh --mode=explore --mock --screenshot=screenshots/fase00_boot.png --quit-after=1.5

# 2. Prueba de flags numéricos y de modo batalla (verifica escape %-%-)
./run.sh --mode=battle --encounter=3 --mock --screenshot=screenshots/fase00_battle_cli.png --quit-after=1.5

# 3. Confirmar que ambos PNG existen y pesan > 10 KB
ls -lh screenshots/fase00_boot.png screenshots/fase00_battle_cli.png
```

### Prompts Cortos de Ajuste Rápido (si algo falla en el Playtest)
- **Si las flags CLI no se reconocen**:
  > *"En `main.lua`, revisa `parseCliArgs`: recuerda que en patrones de Lua `-` es un cuantificador. Escapa todos los guiones literales como `%-%-` (ej. `a:match("^%-%-encounter=(%d+)$")` y `a:match("^%-%-quit%-after=(%d+%.?%d*)$")`). Re-ejecuta el test CLI."*
- **Si `--screenshot` sale en blanco o no se guarda**:
  > *"Asegúrate de disparar `saveScreenshotTo(Game.cliScreenshot)` al menos `0.35s` antes de `love.event.quit()` (`cliElapsed >= cliQuitAfter - 0.35`) y crear el directorio padre `screenshots/` si no existe."*
- **Si el greybox de Modo B se ve confuso**:
  > *"Mejora los placeholders procedurales en `asset_loader.lua` para que el Pudú tenga dirección clara (ojos/hocico apuntando en cada una de las 8 filas) y cada tile de bioma tenga un patrón pixelado sutil distinto."*
