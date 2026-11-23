# Fase 2 — Arena de Batalla Vista Lateral, Iluminación HD-2D, Dash-in (`battle_enter`), Sombrero de Mago y Baile Idle al Compás

| Campo | Detalle |
| :--- | :--- |
| **Fase** | `Fase 02` — Arena Dedicada HD-2D y Animación Musical Idle |
| **Duración estimada en hackathon** | `90 – 120 min` |
| **Prerrequisitos (Gate de entrada)** | • **Fase 1 aprobada**: Overworld diagonal `↗` con 4 biomas, 9 encuentros, cámara calma por salas y transición JRPG `alert -> to_battle` operativa.<br>• `audio.lua` y `asset_loader.lua` funcionales (Modo A o Modo B). |
| **Entregables concretos** | 1. `shaders.lua`: shaders GLSL HD-2D `lit` (normal maps + sol + hasta 10 luces puntuales + rim/specular), `sunbeam` (rayos volumétricos diagonales) y `post` (bloom seguro + viñeta), protegidos con `Shaders.send` / `safeSend` (`hasUniform`).<br>2. `stage_renderer.lua` (bloque Arena de Batalla + HD-2D): escenario vista lateral separado por bioma (8 stages: `plaza`, `bosque`, `mirador`, `vereda`, `muelle`, `pantano`, `esquina`, `oficina`), piso pixel-art en perspectiva (12 bandas normal-mapped), props de fondo y primer plano, 4 presets de luz (`dia`, `atardecer`, `noche`, `dramatico`), faroles cálidos con `light_radial.png` aditivo y post-procesado sobre `worldCanvas`.<br>3. `beat_sync.lua`: sincronizador musical PLL sin jitter anclado a `audio:getTrackState()` (`139.20 BPM`, `beatOffset = 0.342s` + metrónomo autónomo en Modo B), coreografía **solo idle** de 4 tiempos estilo *Mario & Luigi: Superstar Saga* (`battle_idle`), trote de entrada (`battle_enter`), caminata (`walk`), contrapunto del rival (`getEnemyGroove("idle")`) y física de resorte del sombrero (`hatOffsetY`, `hatTilt`).<br>4. Integración en `main.lua`: secuencia `battle_enter` (`0.88s`, dash-in de `320px` tomando posición), dibujo del **sombrero de mago café en punta** (`HAT_HEAD_OFFSETS` por dirección `0..7`), música `user_battle` al entrar a la arena y banderas CLI `--lighting=` y `--battle-enter-preview`. |

---

## 1. Objetivo de Producción y Alcance (Qué SÍ y Qué NO hacer en esta fase)

El objetivo de la Fase 2 es darle a Pudú Fantasy su **firma visual y emocional inolvidable**: al cruzar la transición JRPG, la cámara aterriza en una **arena de batalla vista lateral iluminada en HD-2D** (estilo *Octopath Traveler* con pixel-art, normal maps, faroles cálidos, rayos de sol y bloom controlado), Pudú entra trotando en posición (`battle_enter`) con su **sombrero de mago café en punta** rebotando por inercia y comienza a bailar **al compás exacto de la canción de batalla (`139.20 BPM`, `beatOffset = 0.342s`)** como en *Mario & Luigi: Superstar Saga*.

### Qué SÍ hacer en Fase 2
- **Escenario dedicado vista lateral por bioma (`drawBattleArena` + `drawBattleArenaForeground`)**:
  - Posiciones ancla: Pudú a la izquierda (`0.28 * w`, `0.65 * h`), Rival a la derecha (`0.72 * w`, `0.65 * h`).
  - Cielo pixelado de 12 bandas + sol/luna + estrellas en `noche` + 2 capas de siluetas de horizonte específicas de cada bioma (y el barco `caleuche_ship` flotando en `muelle`).
  - **Piso pixel-art en perspectiva** con **12 bandas escorzadas** (`y = horizonY + floorH * (t^1.32)`, `pScale = lerp(0.46, 1.42, tMid)`) usando los tiles normal-mapped del bioma + detalle central (alfombra roja en `oficina`, paso de cebra en `esquina`, tablones + baranda en `muelle`, elipse de acento en el resto).
  - Props de encuadre lateral (`BATTLE_STAGE_DECOR`) estrictamente en los costados y fondo para **NUNCA tapar a Pudú ni al rival**, más props sutiles de primer plano en las esquinas inferiores (`0.03w` y `0.97w`, `0.84h`).
  - Anillos de postura bajo Pudú (cian-dorado) y Rival (carmesí-dorado) que respiran sutilmente con `beatPulse`.
- **Iluminación HD-2D segura y rápida**:
  - `shaders.lit`: iluminación por normal map (`normalMap`, `hasNormalMap`, `normalStrength`, `spriteAngle`, `spriteBillboard`, `surfaceBaseY`, `specStrength`, `emissiveBoost`), luz direccional + rim light en billboards + hasta 10 luces puntuales (`lightPosRadius[10]`, `lightColorEnergy[10]`).
  - `shaders.sunbeam`: rayos de sol diagonales volumétricos (`beamAngle = -0.44`) dibujados en modo `"add"` usando una textura blanca `2x2` (`_getUnitWhite()`) para garantizar coordenadas UV reales (desactivado automáticamente en preset `noche`).
  - `shaders.post`: bloom controlado (`smoothstep(0.74, 1.0, luma)`) + viñeta cinemática sobre `worldCanvas`.
  - **Blindaje de uniforms (`safeSend` / `Shaders.send`)**: verificar SIEMPRE `shader:hasUniform(name)` antes de `shader:send(...)` para prevenir crashes en drivers OpenGL que eliminan uniforms optimizados.
  - **4 Presets de luz (`LIGHTING_PRESETS`)**: `dia` (*Día Soleado*), `atardecer` (*Atardecer Dorado*), `noche` (*Noche Neón*) y `dramatico` (*Foco Teatral*), más faroles cálidos y cristales (`collectBattleLights`) con halo `light_radial.png` aditivo.
- **Dash-in de Posicionamiento (`battle_enter`)**:
  - Al entrar a la arena, `battlePhase = "battle_enter"`, `battleEnterT` avanza de `0.0` a `1.0` en **`0.88s`**.
  - `slideOff = (1.0 - smoothstep(battleEnterT)) * 320.0`: Pudú entra trotando desde `bxP - slideOff` con `puduAnimMode = "battle_enter"` (row `2` Este, cols `{2, 3, 4, 5}`, zancada enérgica) y el rival desliza desde `bxE + slideOff`.
  - Al llegar a `1.0`, pasa a `battlePhase = "player_turn"` y `puduAnimMode = "battle_idle"`.
- **Sombrero de Mago Café en Punta con física de resorte**:
  - Dibujado sobre la cabeza del Pudú en overworld y batalla usando la tabla `HAT_HEAD_OFFSETS[0..7]` según la dirección (`row`), ajuste de salto cuando `col == 5` (`dashShiftX = flip * 7.0`, `dashShiftY = 6.5`), pivote `(0.50, 0.82)` y escala `sc * 0.92`.
  - Follow-through elástico de `beat_sync.lua`: `hatOffsetY` (desfase vertical de fase `p - 0.42`, flotando en el ápice y asentando en el downbeat) y `hatTilt = tilt * 1.35 + lagSway`.
- **Baile Idle al Compás (`beat_sync.lua` + `audio.lua`)**:
  - Sincronizado por PLL sin jitter (`blend = clamp(dt * 12, 0, 1)`) a `audio:getTrackState()` sobre `user_battle` (`139.20 BPM`, `beatOffset = 0.342s`), con manejo de wrap de loop y metrónomo interno automático si no hay audio.
  - Coreografía fluida de 4 tiempos (`barBeat = 0, 1, 2, 3`) estilo *Mario & Luigi: Superstar Saga*:
    - **Beat 0**: squash de rodillas (`1.10 / 0.89`) -> rebote `-11px`, inclinación `+0.065`, `col 2 -> 3`.
    - **Beat 1**: rebote erguido `-10.5px`, peso atrás-izquierda `-0.075`, micro-giro de torso `row 1 <-> 2`, `col 4`.
    - **Beat 2**: doble paso *upbeat* `-13px`, inclinación `+0.060`, `col 2 -> 3`.
    - **Beat 3**: salto de floritura `-18px` con *tuck* en el aire (`col 1 -> 5 -> 1`).
  - Contrapunto sutil del enemigo (`getEnemyGroove("idle")`): rebote suave `-6.8px` e inclinación opuesta.

### Qué NO hacer en Fase 2 (Reglas Estrictas de Diseño)
- **NO dibujar notas musicales flotando (`♪`, `♫`, partículas musicales)**: `pose.noteSparkle` debe ser `false` SIEMPRE.
- **NO crear ninguna mecánica de seguir el ritmo** (ni barras de timing, ni QTE de compás, ni multiplicadores por pulsar al ritmo).
- **NO agregar ningún botón "Bailar" en la interfaz**: el baile es exclusivamente la animación **idle** natural del Pudú en batalla.
- **NO** construir todavía el HUD completo de prompts, el ritual de flechas ni las llamadas a Gemini (eso viene en la fase de Combate con IA).
- **NO** sobre-ingenierizar en esta fase un motor Deferred MRT + Radiance Cascades 2D GI de 1.000 líneas: el pipeline `lit` + `sunbeam` + `post` + `light_radial` ya entrega look HD-2D sólido a 60 FPS en cualquier laptop de hackathon (el upgrade MRT/GI puede quedar como polish opcional tardío).

---

## 2. Modo Assets: ¿Ya tengo sprites/música o los incorporo después?

### Modo A — Con música de batalla, sombrero, normal maps y `light_radial.png` listos
- **Canción principal**: `assets/audio/battle_user_main.wav` (`139.20 BPM`, `beatOffset = 0.342s`, `37 beats`, `loop = true`). Si el equipo compone o reemplaza la canción por otra en la hackathon, solo debe actualizar `bpm` y `beatOffset` en `Audio.TRACK_META.user_battle` (se puede medir en segundos el primer bombo/downbeat en Audacity o con script Python).
- **Sombrero de mago**: `assets/sprites/gags/pudu_wizard_hat.png` (+ `_n.png` opcional).
- **Normal maps (`*_n.png`)**: para `pudu_8dir_sheet_n.png`, `grass_floor_n.png`, `stone_floor_n.png`, `desert_floor_n.png`, `mountain_floor_n.png`, `coast_floor_n.png`, props y encuentros. El shader `shaders.lit` los detecta automáticamente (`hasNormalMap = 1.0`).
- **Luz radial**: `assets/sprites/light_radial.png` (halo circular suave blanco sobre fondo transparente, filtro `linear`).

### Modo B — Sin arte final ni canción todavía
- **Sin canción `.wav`**: `Audio:playTrack("user_battle")` no falla; `BeatSync:update` detecta `trackPlaying == false` y activa automáticamente su **metrónomo autónomo a `139.20 BPM`**, por lo que Pudú baila fluido en 4 tiempos desde el minuto cero. En cuanto el músico deje `battle_user_main.wav` en `assets/audio/`, el PLL se engancha automáticamente a `source:tell("seconds")` sin cambiar código.
- **Sin normal maps (`_n.png`)**: `shaders.lit` envía `hasNormalMap = 0.0` y usa normal plana `(0, 0, 1)`, manteniendo iluminación direccional, luces de faroles, sunbeams y bloom funcionando sin artefactos.
- **Sin sombrero ni `light_radial.png`**: `asset_loader.lua` entrega el sombrero café puntiagudo procedural y el gradiente radial gaussiano procedural en memoria; reemplazarlos luego con PNGs reales y pulsar `[F5]` actualiza el look al instante.

---

## 3. División Codex vs Astra + Subagentes de esta Fase

| Agente / Rol | Responsabilidad Exacta | Archivos que Toca (Propiedad Exclusiva) |
| :--- | :--- | :--- |
| **Codex (Coordinador)** | Lanza Subagentes A, B y C en paralelo; luego integra en `main.lua` el pipeline de render sobre `worldCanvas`, el dash-in `battle_enter`, `drawPuduSprite` con sombrero de mago y física de resorte, `drawEnemySprite` con `getEnemyGroove`, música `user_battle` y flags CLI (`--lighting`, `--battle-enter-preview`), y corre toda la batería visual CLI. | `main.lua` |
| **Subagente A — Shaders HD-2D Seguros** | Crea `shaders.lua` con `lit`, `sunbeam` y `post`, compilación segura (`compileShader`), detección de warnings (`getWarnings`) y caché de uniforms `Shaders.send` usando `hasUniform`. | `shaders.lua` |
| **Subagente B — BeatSync & Baile Idle Superstar Saga** | Crea `beat_sync.lua` con PLL sin jitter (`139.20 BPM`, `beatOffset = 0.342s`, wrap de loop, fallback autónomo), `evalBeatBounce`, `getPuduDancePose` (`battle_idle`, `battle_enter`, `walk`, `victory`, `hurt`, `cast`, `ritual` preparados con `noteSparkle = false`), física del sombrero (`hatOffsetY`, `hatTilt`) y `getEnemyGroove("idle")`. | `beat_sync.lua` |
| **Subagente C — Arena Vista Lateral e Iluminación en StageRenderer** | Extiende `stage_renderer.lua` añadiendo los 4 `LIGHTING_PRESETS`, `THEME_TILES`, `BATTLE_STAGE_DECOR`, `configureLitShader`, `drawSpriteLit`, `drawBattleArena`, `drawBattleArenaForeground`, `collectBattleLights`, `collectZoneLights`, `drawAtmosphericLighting` (`light_radial` + `sunbeam` con `_getUnitWhite`) y `drawPostProcessed` usando `safeSend` (`hasUniform`). | `stage_renderer.lua` |
| **Astra (Lighting & Animation Director)** | Revisa capturas en los 4 presets de iluminación (`dia`, `atardecer`, `noche`, `dramatico`), la captura a mitad del dash-in (`--battle-enter-preview`) y varios escenarios (`plaza`, `mirador`, `muelle`, `oficina`) auditando contraste, altura/inclinación del sombrero, limpieza sin notas musicales y bloom. | Solo lectura + auditoría visual |

---

## 4. Prompt Maestro para Codex (Copiar y Pegar — Orquestación con Subagentes)

```markdown
Eres el Ingeniero Jefe de Pudú Fantasy en LÖVE2D 11.5. Estamos ejecutando la **Fase 2: Arena de Batalla Vista Lateral, Iluminación HD-2D, Dash-in (`battle_enter`), Sombrero de Mago y Baile Idle al Compás** sobre la base verificada de Fase 1. Lee `AGENTS.md` antes de escribir código.

### Reglas Inquebrantables de Fase 2
- **CERO notas musicales flotando** (`noteSparkle = false` siempre).
- **CERO mecánica de seguir el ritmo**, cero barras de timing y cero botón "Bailar". El baile es exclusivamente animación **idle** expresiva sincronizada al BPM.
- Todos los envíos de uniforms a shaders DEBEN pasar por `hasUniform` (`Shaders.send` / `safeSend`) para evitar crashes en cualquier GPU.
- Todo debe funcionar tanto en **Modo A** (con PNGs/normal maps/WAV reales) como en **Modo B** (placeholders procedurales sin crash).

### Orquestación Obligatoria con 3 Subagentes en Paralelo
Lanza estos 3 subagentes con propiedad exclusiva de archivos:

1. **Subagente A (`shaders.lua`)**:
   - Compila y exporta `Shaders.load()` con 3 shaders obligatorios:
     - `lit`: normal mapping (`normalMap`, `hasNormalMap`, `normalStrength`, `spriteAngle`, `spriteBillboard`, `surfaceBaseY`, `emissiveBoost`, `emissiveColor`, `specStrength`), luz ambiental hemisférica, sol direccional con wrap + specular Blinn-Phong + rim light en billboards, hasta 10 luces puntuales (`numLights`, `lightPosRadius[10]`, `lightColorEnergy[10]`) con atenuación suave y compresión suave de picos > 1.0.
     - `sunbeam`: rayos diagonales volumétricos (`time`, `beamAngle`, `beamColor`, `beamStrength`) con 3 ondas sinusoidales y fade suave en bordes verticales/horizontales.
     - `post`: post-procesado sobre `worldCanvas` (`dofEnabled`, `focusY`, `texelSize`, `bloomStrength`, `vignetteStrength`) con bloom seguro de 4 muestras sobre luma > `0.74` y viñeta cinemática.
   - Implementa `Shaders.send(shaderSet, shaderName, uniform, ...)` con caché de `sh:hasUniform(uniform)` y `Shaders.getWarnings(shaderSet)`.

2. **Subagente B (`beat_sync.lua`)**:
   - Implementa `BeatSync.new(defaultBpm)` (default `139.2`), `reset(bpm)`, `update(dt, trackState, manualBpmOverride)`.
   - Sincronización PLL sin jitter contra `trackState` (`bpm`, `pos`, `duration`, `id`, `beatOffset`, `playing`):
     - Calcula `rawBeat = max(0, (trackPos - trackOffset) * (bpm / 60))`.
     - Detecta wrap de loop cuando `trackPos < _lastTrackPos - 0.25` sumando `loopBeats` a `_loopBeatBase`.
     - Mezcla suave `blend = clamp(dt * 12.0, 0, 1)` manteniendo `beatFloat` estrictamente monotónico (`>= prevBeatFloat`).
     - Si `trackPlaying == false` (Modo B sin WAV), avanza limpiamente con metrónomo autónomo (`predicted = prevBeatFloat + dt * beatsPerSec`).
   - Implementa `evalBeatBounce` (squash C1 coseno elevado en downbeat + salto elástico boyante `arc * (1.14 - 0.14 * arc)`).
   - Implementa `getPuduDancePose(mode, facingDirOverride)` retornando `{ row, col, scaleX, scaleY, jumpY, tilt, stepX, stepY, hatOffsetY, hatTilt, noteSparkle = false }`:
     - `battle_idle`: coreografía de 4 beats estilo *Mario & Luigi: Superstar Saga* en vista 3/4 derecha (`baseRow = 1`):
       - `bar == 0`: squash `0.10/0.11`, hop `-11.0`, tilt `+0.065`, `col 2 -> 3`
       - `bar == 1`: squash `0.085/0.095`, hop `-10.5`, tilt `-0.075`, giro sutil de torso `row 1 <-> 2`, `col 4`
       - `bar == 2`: squash `0.105/0.115`, hop `-13.0`, tilt `+0.060`, `col 2 -> 3`
       - `bar == 3`: flourish hop `-18.0`, `col 1 -> 5 -> 1`
       - Física de resorte del sombrero: `lagSin = sin((p - 0.42) * TWO_PI)`, `hatOffsetY = (-0.85 * hopWeight - (2.55 + 0.95 * hopWeight) * lagSin) * inten`, `hatTilt = tilt * 1.35 + sin((bf - 0.18) * pi) * 0.065 * inten`.
     - `battle_enter`: trote enérgico hacia la derecha (`row = 2`, cols `{2, 3, 4, 5}`, `jumpY` de zancada, sombrero retrasado por inercia).
     - `walk`: caminata rítmica para el overworld (`cols {2, 3, 4, 3}`).
     - Deja también listas las poses base `victory`, `hurt`, `cast`, `ritual` (todas con `noteSparkle = false`).
   - Implementa `getEnemyGroove("idle")` en contrapunto suave al Pudú (`hop = 6.8`, `offsetX = -sin(bf * pi) * 3.0`, `tilt = -sin(bf * pi) * 0.048`).

3. **Subagente C (`stage_renderer.lua`)**:
   - Conserva íntegro todo el Overworld de Fase 1 y añade el subsistema HD-2D + Arena de Batalla:
     - `LIGHTING_PRESETS` y `LIGHTING_ORDER`: `dia`, `atardecer`, `noche`, `dramatico` con `ambientMul`, `sunEnergy`, `sunColor`, `sunDir`, `skyTint`, `vignette`, `bloomStrength`.
     - `THEME_TILES` y `BATTLE_STAGE_DECOR` para los 8 stages (`plaza`, `bosque`, `mirador`, `vereda`, `muelle`, `pantano`, `esquina`, `oficina`), manteniendo el centro libre para los combatientes.
     - `configureLitShader(theme, screenW, screenH, time, extraLights)` y `drawSpriteLit(spritePair, x, y, angle, sx, sy, ox, oy, quadObj, emissiveBoost, emissiveCol, litShader)` integrándolo también al piso/props del overworld cuando `useLitShader == true`.
     - `drawBattleArena(encounter, stageThemes, propSprites, beatPulse, w, h, time, litShader)`: cielo (`horizonFrac = 0.44`), `caleuche_ship` en `muelle`, piso pixel-art en perspectiva de 12 bandas escorzadas (`t^1.32`, `pScale 0.46 -> 1.42`) con normal maps y neblina de horizonte, detalle central por stage (alfombra roja en `oficina`, cebra en `esquina`, tablones+baranda en `muelle`), props de fondo ordenados por `y`, y anillos de postura que laten con `beatPulse`.
     - `drawBattleArenaForeground(encounter, propSprites, w, h, litShader)`: props sutiles en esquinas `0.03w` y `0.97w` a `0.84h`.
     - `collectZoneLights` y `collectBattleLights` (faroles cálidos, cristales cian, faro).
     - `drawAtmosphericLighting(lightRadialImg, lights, w, h, time)`: halos aditivos con `light_radial` + rayos `shaders.sunbeam` (`beamAngle = -0.44`, usando textura `2x2` `_getUnitWhite()`, apagado en `noche`).
     - `drawPostProcessed(worldCanvas, w, h)` usando `safeSend` con `hasUniform`.

### Integración en `main.lua` (Coordinador)
- Carga `shaders = Shaders.load()`, `beatSync = BeatSync.new(139.2)` y crea `worldCanvas` redimensionable (`ensureWorldCanvas(w, h)`).
- Al entrar a batalla (`enterBattleArenaImmediate(idx, skipEnterDash)`):
  - Inicia `Game.battlePhase = skipEnterDash and "player_turn" or "battle_enter"`, `Game.battleEnterT = skipEnterDash and 1.0 or 0.0`, `Game.puduAnimMode = skipEnterDash and "battle_idle" or "battle_enter"`.
  - Dispara `audio:playTrack("user_battle", false)` y `beatSync:reset(audio:getTrackState().bpm or 139.2)`.
- En `love.update(dt)`:
  - Actualiza `beatSync:update(dt, audio:getTrackState())`.
  - Durante `battlePhase == "battle_enter"`, avanza `Game.battleEnterT = min(1.0, Game.battleEnterT + dt / 0.88)`; al llegar a `1.0`, pasa a `player_turn` y `puduAnimMode = "battle_idle"`.
- En `love.draw()`:
  - Durante `battle_enter`, calcula `slideOff = (1.0 - smoothstep(Game.battleEnterT)) * 320.0`, `puduX = bxP - slideOff`, `enemyX = bxE + slideOff`.
  - Renderiza el mundo (Overworld o Arena) en `worldCanvas` con `litShader` + `drawPuduSprite` (incluyendo **sombrero de mago café** con `HAT_HEAD_OFFSETS[0..7]`, `dashShift` en `col == 5`, `hatOffsetY` y `hatTilt`) + `drawEnemySprite` (con `getEnemyGroove("idle")`) + `drawBattleArenaForeground` + `drawAtmosphericLighting`.
  - Vuelca `worldCanvas` a pantalla vía `stage:drawPostProcessed(worldCanvas, w, h)` y dibuja encima el minimapa/UI nítida sin bloom.
- Añade teclas rápidas temporales de test en Fase 2: tecla `L` cicla presets de iluminación (`dia -> atardecer -> noche -> dramatico`) y `1..9` salta de encuentro en modo batalla para probar las 8 arenas.
- Añade flags CLI (con `%-%-`): `--lighting=(.+)` y `--battle-enter-preview`.

### Verificación CLI Obligatoria al Terminar
Ejecuta estas pruebas y verifica exit code `0`, cero warnings GLSL y capturas válidas:
1. `./run.sh --mode=battle --encounter=1 --lighting=dia --mock --screenshot=screenshots/fase02_plaza_dia.png --quit-after=1.8`
2. `./run.sh --mode=battle --encounter=1 --lighting=atardecer --mock --screenshot=screenshots/fase02_plaza_atardecer.png --quit-after=1.8`
3. `./run.sh --mode=battle --encounter=1 --lighting=noche --mock --screenshot=screenshots/fase02_plaza_noche.png --quit-after=1.8`
4. `./run.sh --mode=battle --encounter=6 --lighting=dramatico --mock --screenshot=screenshots/fase02_muelle_dramatico.png --quit-after=1.8`
5. `./run.sh --mode=battle --encounter=9 --lighting=dia --mock --screenshot=screenshots/fase02_oficina_dia.png --quit-after=1.8`
6. `./run.sh --mode=battle --encounter=1 --battle-enter-preview --mock --screenshot=screenshots/fase02_battle_enter.png --quit-after=0.45`
```

---

## 5. Prompts Individuales por Subagente (Opcional si el equipo divide tareas)

### Subagente A — `shaders.lua`
```markdown
Crea `shaders.lua` para Pudú Fantasy (LÖVE2D 11.5) según `AGENTS.md`.
Implementa los shaders GLSL `lit` (normal map opcional, sol direccional con rim/specular, hasta 10 luces puntuales con atenuación suave), `sunbeam` (rayos diagonales volumétricos animados) y `post` (bloom seguro + viñeta).
Incluye `Shaders.load()`, `Shaders.send(shaderSet, shaderName, uniform, ...)` verificando siempre `sh:hasUniform(uniform)` con caché, y `Shaders.getWarnings(shaderSet)`. No edites otros archivos.
```

### Subagente B — `beat_sync.lua`
```markdown
Crea `beat_sync.lua` para Pudú Fantasy según `AGENTS.md`.
Implementa `BeatSync.new(139.2)`, `reset`, `update(dt, trackState)` con PLL sin jitter (mezcla `dt * 12`, manejo de `beatOffset = 0.342s`, detección de loop wrap y fallback a metrónomo autónomo si no hay audio), `getPuduDancePose` con la coreografía de 4 tiempos `battle_idle` estilo Mario & Luigi Superstar Saga, `battle_enter`, `walk`, y física de resorte del sombrero (`hatOffsetY`, `hatTilt`), además de `getEnemyGroove("idle")`.
REGLA ESTRICTA: `noteSparkle = false` siempre (nunca emitir notas musicales) y sin mecánicas de juego rítmico. No edites otros archivos.
```

### Subagente C — `stage_renderer.lua` (Arena HD-2D + Iluminación)
```markdown
Extiende `stage_renderer.lua` preservando todo el Overworld de Fase 1 para agregar la Arena de Batalla HD-2D:
- `LIGHTING_PRESETS` (`dia`, `atardecer`, `noche`, `dramatico`), `THEME_TILES` y `BATTLE_STAGE_DECOR` para los 8 stages.
- `configureLitShader` y `drawSpriteLit` (aplicable a sprites y patches isométricos).
- `drawBattleArena` (cielo `0.44h`, piso pixel-art en perspectiva de 12 bandas escorzadas `t^1.32` con normal maps, props laterales y anillos de postura pulsantes con `beatPulse`) y `drawBattleArenaForeground`.
- `collectBattleLights`, `collectZoneLights`, `drawAtmosphericLighting` (`light_radial` aditivo + `shaders.sunbeam` con `_getUnitWhite`) y `drawPostProcessed` usando `safeSend` con `hasUniform`.
No modifiques `main.lua`.
```

---

## 6. Prompt para Astra (Design Review & Auditoría Visual de la Fase)

> **Adjunta a Astra**: `screenshots/fase02_plaza_dia.png`, `screenshots/fase02_plaza_atardecer.png`, `screenshots/fase02_plaza_noche.png`, `screenshots/fase02_muelle_dramatico.png`, `screenshots/fase02_oficina_dia.png` y `screenshots/fase02_battle_enter.png`.

```markdown
Eres Astra, Directora de Arte e Iluminación de Pudú Fantasy. Audita las 6 capturas de la **Fase 2 (Arena HD-2D, Presets de Luz, Dash-in, Sombrero de Mago y Baile Idle)**.

Revisa estrictamente estos criterios:
1. **Identidad HD-2D e Iluminación**: Compara `dia`, `atardecer`, `noche` y `dramatico`. ¿Los faroles cálidos (`light_radial`) y los sunbeams aportan profundidad atmosférica sin quemar los blancos ni oscurecer demasiado al Pudú en `noche`?
2. **Composición de la Arena Vista Lateral**: En `plaza`, `muelle` y `oficina`, ¿el horizonte (`0.44h`), las 12 bandas de suelo en perspectiva y los props laterales enmarcan bien el duelo sin tapar jamás a Pudú (`0.28w`) ni al rival (`0.72w`)?
3. **Sombrero de Mago Café**: ¿Está bien asentado en la cabeza del Pudú en tamaño, ángulo y pivote? ¿Se ve encantador tanto en `battle_enter` (corriendo) como en `battle_idle`?
4. **Regla de Pureza de Baile Idle**: Confirma explícitamente que NO hay notas musicales flotando, NO hay barras de ritmo ni botón "Bailar".
5. **Veredicto**: `APROBADO PARA FASE 3` o `AJUSTAR ANTES DE FASE 3` con máximo 4 correcciones concretas (valores de escala, offset del sombrero, energía de luz o contraste).
```

---

## 7. Gate de Iteración en Equipo (Playtest de 5 min + Definition of Done)

### Guion de Playtest Manual (5 minutos)
1. **Minuto 0–1 (Transición + Dash-in)**: Desde el overworld, camina hacia el primer rival. Confirma que tras las persianas JRPG se abre la arena dedicada y **Pudú entra trotando desde la izquierda (`0.88s`)** hasta posicionarse en `0.28w` mientras el rival entra por la derecha.
2. **Minuto 1–2.5 (Baile Idle al Compás y Sombrero)**: Quédate sin tocar teclas durante 20 segundos escuchando la canción (`139.20 BPM`). Observa el ciclo de 4 tiempos (squash de rodillas -> rebote con giro -> doble paso -> saltito flourish) y cómo el **sombrero de mago café** flota y cae con ligero retraso elástico. Comprueba que **no hay notas musicales flotando** y que el rival hace su contrapunto suave.
3. **Minuto 2.5–3.5 (Presets HD-2D y Mute sin Desync)**: Presiona `L` para ciclar `dia -> atardecer -> noche -> dramatico`. Comprueba faroles cálidos en `noche`, rayos dorados en `atardecer` y cero crashes de shader. Presiona `M` para mutear y desmutear: el baile debe seguir exactamente en fase con el compás.
4. **Minuto 3.5–5 (Variedad de Escenarios + `[F5]`)**: Cicla encuentros (`1` a `9`) para revisar las 8 arenas (`plaza`, `bosque`, `mirador`, `vereda`, `muelle`, `pantano`, `esquina`, `oficina`). Prueba `[F5]` y `Esc` para volver al overworld.

### Checklist de Definition of Done (DoD)
- [ ] Al entrar a batalla se dispara el dash-in `battle_enter` (`0.88s`) y transiciona suavemente a `battle_idle`.
- [ ] Pudú ejecuta los 4 beats del baile idle estilo *Mario & Luigi: Superstar Saga* sincronizado a `139.20 BPM` (`beatOffset = 0.342s`), sin drift ni saltos al hacer loop.
- [ ] El sombrero de mago café sigue la cabeza del Pudú en las 8 direcciones con física elástica (`hatOffsetY`, `hatTilt`).
- [ ] Confirmado: **cero notas musicales flotando**, **cero UI de ritmo**, **cero botón "Bailar"**.
- [ ] Los 4 presets de luz (`dia`, `atardecer`, `noche`, `dramatico`) renderizan a 60 FPS sin errores de `hasUniform` ni warnings GLSL.
- [ ] Funciona tanto en Modo A (con `battle_user_main.wav` y normal maps `_n.png`) como en Modo B (greybox + metrónomo autónomo).
- [ ] Las 6 capturas CLI terminan con exit code `0` y aprobación de Astra.

### Comandos Exactos de Verificación
```bash
# 1. Los 4 presets de iluminación HD-2D en batalla
./run.sh --mode=battle --encounter=1 --lighting=dia       --mock --screenshot=screenshots/fase02_plaza_dia.png       --quit-after=1.8
./run.sh --mode=battle --encounter=1 --lighting=atardecer --mock --screenshot=screenshots/fase02_plaza_atardecer.png --quit-after=1.8
./run.sh --mode=battle --encounter=1 --lighting=noche     --mock --screenshot=screenshots/fase02_plaza_noche.png     --quit-after=1.8
./run.sh --mode=battle --encounter=6 --lighting=dramatico --mock --screenshot=screenshots/fase02_muelle_dramatico.png --quit-after=1.8

# 2. Arena final (Oficina) + captura a mitad del dash-in battle_enter
./run.sh --mode=battle --encounter=9 --lighting=dia --mock --screenshot=screenshots/fase02_oficina_dia.png --quit-after=1.8
./run.sh --mode=battle --encounter=1 --battle-enter-preview --mock --screenshot=screenshots/fase02_battle_enter.png --quit-after=0.45
```

### Prompts Cortos de Ajuste Rápido (si algo no se siente bien)
- **Si el baile parece adelantado o atrasado respecto a tu canción nueva**:
  > *"En `audio.lua`, ajusta `TRACK_META.user_battle.bpm` y `beatOffset` (en segundos del primer golpe fuerte) para nuestra canción actual, manteniendo `loop = true` y `static`. Re-verifica `beat_sync.lua`."*
- **Si el sombrero café queda ligeramente alto, bajo o corrido en algún ángulo**:
  > *"En `main.lua`, ajusta `HAT_HEAD_OFFSETS` (especialmente `[1]` y `[2]` para batalla, y `dashShiftY` para `col == 5`) y `hatScale = sc * 0.92` hasta que el ala abrace exactamente la cabeza del Pudú."*
- **Si el preset `noche` queda demasiado oscuro o el bloom se ve excesivo**:
  > *"En `stage_renderer.lua`, sube `LIGHTING_PRESETS.noche.ambientMul` de `{0.34, 0.42, 0.68}` a `{0.42, 0.50, 0.74}` y reduce `bloomStrength` en `drawPostProcessed` de `0.30` a `0.22`. Vuelve a capturar `fase02_plaza_noche.png`."*
- **Si alguna GPU reporta error de uniform en shaders**:
  > *"Revisa `stage_renderer.lua` para asegurar que TODAS las llamadas `:send(...)` en `lit`, `sunbeam` y `post` pasen por `safeSend(shader, name, ...)` verificando `shader:hasUniform(name)`."*
