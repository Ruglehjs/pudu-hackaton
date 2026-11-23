# Fase 1 — Vertical Slice Overworld: Mapa Diagonal `↗`, 4 Biomas Irregulares, Cámara Calma por Salas y Transición JRPG

| Campo | Detalle |
| :--- | :--- |
| **Fase** | `Fase 01` — Exploración Overworld y Transición a Batalla |
| **Duración estimada en hackathon** | `90 – 120 min` |
| **Prerrequisitos (Gate de entrada)** | • **Fase 0 aprobada**: `conf.lua`, `run.sh`, `AGENTS.md`, `asset_loader.lua`, `audio.lua`, `json.lua` y Harness CLI funcionando con exit code `0`.<br>• Decisión tomada sobre **Modo A** (tiles/props reales en `assets/`) o **Modo B** (greybox procedural). |
| **Entregables concretos** | 1. `encounters.lua`: catálogo real de **4 biomas** (`bosque`, `desierto`, `costa`, `ciudad`), **8 temas de escenario** y **9 encuentros** ubicados de `u = 10` a `u = 112` con sus diálogos sin spoiler + `semiHintLine` reservado.<br>2. `stage_renderer.lua` (bloque Overworld): proyección isométrica diagonal **`↗`** (`ISO_UX = 62`, `ISO_UY = -31`, `ISO_VX = 62`, `ISO_VY = 31`, `ELEV_PX = 26`), terreno irregular con elevaciones 3D y faldas/pilotes (`_drawTileSkirts`), río + puente, océano + muelle, acrópolis + alfombra roja.<br>3. Sistema de colisiones deslizables (`StageRenderer.isWalkable` + `screenVecToIso`).<br>4. **Cámara fija por sala (room-snapped)** (`ROOM_SPACING = 14.0`, `camPanDuration = 0.65s`, cero mareo).<br>5. **Minimapa diagonal `↗`** (`212x122` px) + flechas doradas *wayfinder* + anillos beacon bajo rivales.<br>6. **Transición JRPG clásica** (alerta `!` de `0.40s` -> doble flash + 10 persianas diagonales + rombo dorado de `1.05s`) al chocar con un rival (`dist < 1.75`) hacia una escena separada de batalla (placeholder temporal hasta Fase 2) y retorno limpio (`to_explore`, `0.72s`). |

---

## 1. Objetivo de Producción y Alcance (Qué SÍ y Qué NO hacer en esta fase)

El objetivo de la Fase 1 es que el jugador sienta desde el primer segundo que está caminando por un **gran viaje chileno tipo JRPG clásico (Final Fantasy / Pokémon / Octopath)** que asciende en diagonal desde abajo-izquierda (**Bosque Valdiviano**, `u = 0`) hasta arriba-derecha (**Ciudad y Gran Oficina**, `u = 118`), con terreno vivo en 3D, una cámara **serena** que nunca marea y una transición emocionante al toparse con cada uno de los 9 rivales.

### Qué SÍ hacer en Fase 1
- **Mapa grande isométrico diagonal `↗`** (`WORLD_U_MIN = -2.0` a `WORLD_U_MAX = 118.0`) con camino serpenteante (`pathCenterV(u) = sin(u * 0.14) * 2.4 + cos(u * 0.07) * 1.1`), **6 alcobas laterales explorables (`SIDE_ALCOVES`)** y 9 claros de encuentro:
  1. **Bosque y Plaza Valdiviana** (`bosque`, `u = 0..38/40`): `grass_floor` + `stone_floor`, lomas musgosas, río valdiviano (`u ≈ 27.0..30.4`) cruzado por puente de madera (`u = 26.3..31.1`) y arcos de frontera. Rivales: *Niño del Helado Triple* (`u=10, v=0.2`), *Mimo del Muro Invisible* (`u=22, v=-2.0`), *Puma Dramático* (`u=34, v=1.6`).
  2. **Desierto de Atacama** (`desierto`, `u = 38/40..64/66`): `desert_floor` + `stone_floor`, gran meseta rojiza elevada (`+1.05` en `u = 40.5..58.0`), terrazas de arenisca, cactus, cristales y mirador. Rivales: *Turista del Selfie Infinito* (`u=48, v=-1.2`), *Gato Guatón Inamovible* (`u=60, v=1.8`).
  3. **Costa y Muelle de Valparaíso** (`costa`, `u = 64/66..90/92`): `coast_floor` + `stone_floor`, océano animado (`u = 67.4..82.6`, `elev = -0.42`) bajo muelle de tablones con pilotes de madera (`+0.42`), faro, barco Caleuche y pantano (`u = 82.8..90.8`). Rivales: *Gaviota Mafiosa* (`u=74, v=-1.4`), *Pantano Traicionero* (`u=86, v=1.2`).
  4. **Ciudad y Gran Oficina** (`ciudad`, `u = 90/92..118`): `stone_floor` + `mountain_floor`, acrópolis de piedra en 2 terrazas (`u = 93..96` y `u = 105..108.5`) y alfombra roja con borde dorado (`u = 104.5..114.5`). Rivales: *Semáforo Rebelde* (`u=99, v=-0.8`), *Tótem de la Fila #999* (`u=112, v=0.4`).
- **Terreno irregular 3D con oclusión correcta**: iterar celdas de `STEP = 1.5` en orden topológico estricto (**`u` descendente, `v` ascendente**) con faldas verticales izquierda/derecha (`_drawTileSkirts`) y ordenamiento Y-sort (`sortY`) unificado de props verticales + Pudú + rivales.
- **Movimiento cómodo con deslizamiento**: WASD / Flechas convertidos a coordenadas diagonales con `screenVecToIso(dx, dy, 6.2)`, orientación de 8 direcciones del Pudú (`row 0..7`), y chequeo por ejes separados en `isWalkable` (intenta `(candU, candV)` -> `(candU, puduV)` -> `(puduU, candV)` para deslizarse suavemente por bordes de ríos, acantilados y muelles).
- **Cámara calma fija por sala (room-snapped)**: `ROOM_SPACING = 14.0` (9 salas centradas en `cu = min(113, 6 + idx * 14)`), `camZoom = 0.72`. La cámara queda **100% inmóvil** dentro de la sala; solo hace **un único paneo suave `smoothstep` de `0.65s`** cuando `|puduU - camTargetU| > 7.4` o `|puduV - camTargetV| > 5.4`, pausando la entrada de caminata durante ese paneo.
- **Minimapa diagonal `↗`** en la esquina superior izquierda (`x = 14, y = 54`, `212x122` px) mostrando las 4 franjas de bioma, el camino en S, los 9 encuentros (rojo/ámbar activos, verde derrotados), el punto cian del Pudú y la flecha `↗`.
- **Colisión con rival -> Alerta `!` -> Transición JRPG -> Escena separada**: al acercarse a un rival no derrotado (`dist < 1.75`) o pulsar `Tab`, aparece la caja blanca/roja con `!` durante `0.40s` (+ sonido `sfx_encounter_start`), seguida del doble flash blanco + cierre de 10 persianas diagonales + rombo dorado (`1.05s`) que conmuta `Game.mode = "battle"` exactamente en `p >= 0.50` y abre en un escenario temporal limpio (con botón/tecla `Esc` o `Tab` para regresar al overworld vía `to_explore`).
- **Banderas CLI de verificación de Fase 1**: `--biome=bosque|desierto|costa|ciudad`, `--encounter=1..9`, `--transition-preview=0.35`.

### Qué NO hacer en Fase 1
- **NO** implementar seguimiento continuo de cámara (*spring/lerp follow*) que se mueva en cada paso del Pudú: eso marea en vista isométrica y viola la especificación.
- **NO** construir todavía la arena HD-2D definitiva, normal maps avanzados, sunbeams ni el baile sincronizado al BPM (eso es **Fase 2**; en Fase 1 la pantalla destino de batalla puede ser un escenario limpio temporal con los dos combatientes y etiqueta *"Arena lista para Fase 2 — [ESC] volver al mapa"*).
- **NO** meter combates con IA, prompts ni HUD de batalla complejo todavía.

---

## 2. Modo Assets: ¿Ya tengo sprites/música o los incorporo después?

### Modo A — Con sprites de tiles, props, Pudú y rivales listos
- **Tiles de suelo** (`assets/tiles/`): `grass_floor.png`, `stone_floor.png`, `desert_floor.png`, `mountain_floor.png`, `coast_floor.png` (se proyectan a isométrico 2:1 con `scale(camZoom, camZoom * 0.5)` + `rotate(-math.pi * 0.25)` y UV ancladas al mundo para cero costuras entre celdas).
- **Props icónicos de bioma** (`assets/sprites/`): `ancient_tree`, `araucaria_tree`, `valdivian_fern`, `valdivian_shrub`, `copihue`, `calafate_bush`, `mossy_boulder`, `mossy_log`, `lantern_post`, `stone_pedestal`, `rewe_totem`, `orb_shrine`, `wooden_bridge`, `biome_arch`, `desert_cactus`, `mountain_crystal`, `apacheta_sundial`, `rock_monolith`, `moai_relic`, `crystal_mirror`, `lettuce_truck`, `coast_lighthouse`, `caleuche_ship`, `pincoya_shrine`, `log_dam`, `lily_pad`, `textile_bale`, `debris_pile`, `quena_monolith`.
- **Rivales**: los 8 estáticos en `assets/sprites/encounters/<id>.png` y el Puma animado en `assets/sprites/puma_painterly_sheet.png` (`isSheet = true`, `sheetCols = 4`, `sheetRows = 2`, `sheetRow = 1`).
- **Música**: `assets/audio/battle_overworld_lyria.ogg` (`116.04 BPM`) y `assets/audio/sfx_encounter_start.wav`.

### Modo B — Sin arte final (Greybox / Arte progresivo)
- **Terreno**: `stage_renderer.lua` ya posee colores base por bioma (`BIOME_VISUALS[id].miniCol`, `cliffLeft`, `cliffRight`, `cliffLip`) y `asset_loader.lua` entrega tiles procedurales con textura sutil para que el relieve 3D, las faldas de los acantilados, el río, el puente, el muelle con pilotes y la alfombra roja de la oficina se vean nítidos y diferenciables sin ningún PNG.
- **Props y Rivales**: si falta algún prop en `assets.props[key]`, el renderer dibuja un marcador geométrico limpio en escala correcta (árbol/cactus/farol/arco estilizado o el placeholder de `asset_loader.lua`) y cada rival muestra su silueta coloreada + cartel pequeño con su nombre sobre el anillo beacon.
- **Cómo incorporar arte después**: conforme los artistas terminen cada bioma o enemigo, guardan el PNG en `assets/sprites/` o `assets/custom/<id>.png` y pulsan **`[F5]`** para verlo en el mapa en tiempo real, sin tocar Lua.

---

## 3. División Codex vs Astra + Subagentes de esta Fase

| Agente / Rol | Responsabilidad Exacta | Archivos que Toca (Propiedad Exclusiva) |
| :--- | :--- | :--- |
| **Codex (Coordinador)** | Lanza Subagentes A y B en paralelo, integra el loop de exploración, colisiones, alertas `!`, máquina de estados de transición (`none` / `alert` / `to_battle` / `to_explore`) y flags CLI (`--biome`, `--transition-preview`) en `main.lua`, y corre capturas de los 4 biomas + transición. | `main.lua` |
| **Subagente A — Catálogo del Mundo y 9 Encuentros** | Crea `encounters.lua` completo con `BIOME_ORDER`, `BIOMES`, `STAGE_THEME_ORDER`, `STAGE_THEMES`, `LIST` (los 9 encuentros con coordenadas `u, v`, escalas, diálogos y `semiHintLine`), helpers de consulta (`getById`, `getByIndex`, `getTheme`, `getBiome`, `getBiomeAtU`) y persistencia `loadOverrides`/`saveOverrides`. | `encounters.lua` |
| **Subagente B — Motor Overworld Isométrico, Cámara Calma, Minimapa y Transición** | Crea `stage_renderer.lua` con la geometría `↗`, relieve irregular 3D (`getElevation`, `getTerrainType`, `isWalkable`, `pathCenterV`, `screenVecToIso`), `buildOverworldDecor` (landmarks + clusters procedurales), cámara fija por sala (`roomCenter`, `snapCameraToChunk`, `updateExploreCamera`), `drawSkyAndHorizon`, `drawOverworld`, `drawOverworldMinimap` y `drawBattleTransition`. | `stage_renderer.lua` |
| **Astra (Design & Camera Auditor)** | Inspecciona las 5 capturas (los 4 biomas + transición JRPG en progreso) y revisa lectura espacial diagonal `↗`, separación visual entre biomas, proporción Pudú/rivales, legibilidad del minimapa y sensación de calma de cámara. | Solo lectura + crítica de diseño |

---

## 4. Prompt Maestro para Codex (Copiar y Pegar — Orquestación con Subagentes)

```markdown
Eres el Ingeniero Jefe de Pudú Fantasy en LÖVE2D 11.5. Estamos ejecutando la **Fase 1: Vertical Slice Overworld** sobre la base verificada de Fase 0. Lee primero `AGENTS.md` y respeta todos sus contratos.

### Objetivo de Fase 1
Construir el gran Overworld isométrico diagonal (`↗` abajo-izquierda `u=0` -> arriba-derecha `u=118`) con 4 biomas irregulares en 3D, 9 encuentros ubicados a lo largo del viaje, cámara calma fija por salas (room-snapped), minimapa diagonal `↗`, colisiones deslizables y transición JRPG (`!` + flash + persianas diagonales) hacia la pantalla de batalla.

### Orquestación Obligatoria con 2 Subagentes en Paralelo
Lanza estos 2 subagentes con propiedad exclusiva de archivos:

1. **Subagente A (`encounters.lua`)**:
   - Define `Encounters.BIOME_ORDER = { "bosque", "desierto", "costa", "ciudad" }` y `Encounters.BIOMES`:
     - `bosque` ("Bosque y Plaza Valdiviana", `uStart = 0, uEnd = 38`)
     - `desierto` ("Desierto de Atacama", `uStart = 38, uEnd = 64`)
     - `costa` ("Costa y Muelle de Valparaíso", `uStart = 64, uEnd = 90`)
     - `ciudad` ("Ciudad y Gran Oficina", `uStart = 90, uEnd = 118`)
   - Define `Encounters.STAGE_THEME_ORDER` y `Encounters.STAGE_THEMES` para los 8 stages: `plaza`, `bosque`, `mirador`, `vereda`, `muelle`, `pantano`, `esquina`, `oficina` (con `skyTop`, `skyBot`, `horizonGlow`, `groundA`, `groundB`, `pathA`, `pathB`, `accentColor`, `ambientColor`, `sunColor`, `sunDir`, `sunEnergy`, `props`).
   - Define `Encounters.LIST` con exactamente estos 9 encuentros y sus coordenadas `(u, v)`:
     1. `nino_helado` — Niño del Helado Triple (`bosque`, stage `plaza`, `u=10.0, v=0.2`, `scale=2.55`)
     2. `mimo_muro` — Mimo del Muro Invisible (`bosque`, stage `plaza`, `u=22.0, v=-2.0`, `scale=2.55`)
     3. `puma_dramatico` — Puma Dramático (`bosque`, stage `bosque`, `u=34.0, v=1.6`, `isSheet=true, sheetCols=4, sheetRows=2, sheetRow=1, scale=2.55`)
     4. `turista_selfie` — Turista del Selfie Infinito (`desierto`, stage `mirador`, `u=48.0, v=-1.2`, `scale=2.55`)
     5. `gato_guaton` — Gato Guatón Inamovible (`desierto`, stage `vereda`, `u=60.0, v=1.8`, `scale=2.45`)
     6. `gaviota_mafiosa` — Gaviota Mafiosa (`costa`, stage `muelle`, `u=74.0, v=-1.4`, `scale=2.45`)
     7. `piscina_barro` — Pantano Traicionero (`costa`, stage `pantano`, `u=86.0, v=1.2`, `scale=2.65`)
     8. `semaforo_rebelde` — Semáforo Rebelde (`ciudad`, stage `esquina`, `u=99.0, v=-0.8`, `scale=2.65`)
     9. `fila_tramite` — Tótem de la Fila #999 (`ciudad`, stage `oficina`, `u=112.0, v=0.4`, `scale=2.65`)
   - Incluye `introLine` sin spoiler, `semiHintLine` sutil, `weaknesses`, `defeatLine`, `maxHp`, `moodLabel`, y helpers `count`, `getById`, `getByIndex`, `getTheme`, `getBiome`, `getBiomeAtU`, `loadOverrides`, `saveOverrides`.

2. **Subagente B (`stage_renderer.lua`)**:
   - Constantes exactas: `ISO_UX = 62.0`, `ISO_UY = -31.0`, `ISO_VX = 62.0`, `ISO_VY = 31.0`, `ELEV_PX = 26.0`, `ROOM_SPACING = 14.0`, `WORLD_U_MIN = -2.0`, `WORLD_U_MAX = 118.0`, `camZoom = 0.72`, `camPanDuration = 0.65`.
   - Funciones estáticas de terreno:
     - `pathCenterV(u) = math.sin(u * 0.14) * 2.4 + math.cos(u * 0.07) * 1.1`
     - `getBiomeAt(u)` (`<40 bosque`, `<66 desierto`, `<92 costa`, else `ciudad`)
     - `getElevation(u, v)`: puente sobre río en Bosque (`u=26.3..31.1`), río (`-0.35`), océano de Costa (`u=67.4..82.6`, `-0.42`), meseta de Atacama (`+1.05` en `u=40.5..58.0`), muelle (`+0.42`), acrópolis en 2 niveles en Ciudad (`u=93..118`), flancos irregulares y terrazas de acantilado, respetando claros de encuentro y 6 `SIDE_ALCOVES`.
     - `getTerrainType(u, v)`: `"bridge"`, `"river"`, `"water"`, `"carpet"` (alfombra roja en `u=104.5..114.5, |v-0.4|<=1.35`), `"pier"`, `"marsh"`, `"alcove"`, `"path"`, `"cliff"`, `"ground"`.
     - `isWalkable(u, v)`: bloquea bordes de mundo, río fuera del puente, océano fuera del muelle, elevación `>= 2.15` y `|v - pc| > 4.45`, permitiendo siempre claros de encuentro y alcobas laterales.
     - `screenVecToIso(dx, dy, speed)` y `getBattleAnchors(w, h)` (`0.28w, 0.65h` y `0.72w, 0.65h`).
   - Cámara calma por salas:
     - `roomCenter(u)`: 9 salas discretas (`idx = 0..8`, `cu = min(113.0, 6.0 + idx * 14.0)`).
     - `snapCameraToChunk(u, v)`, `updateExploreCamera(puduU, puduV)` (100% inmóvil dentro de la sala; solo inicia paneo `smoothstep` de `0.65s` cuando `du > 7.4` o `dv > 5.4`), `isCameraPanning()`.
   - Renderizado Overworld:
     - `drawSkyAndHorizon(theme, w, h, time, horizonFrac, stageKind)` (cielo 12 bandas + sol + nubes pixeladas + 2 capas de horizonte por bioma).
     - `drawOverworldFloor`: suelo base continuo por bioma + grilla irregular `STEP = 1.5` iterada en orden **`u` descendente, `v` ascendente**, con `_drawTileSkirts` (faldas 3D de acantilado y pilotes de muelle), `_drawWaterTile` animado, flechas doradas *wayfinder* `↗` y anillos beacon bajo cada rival.
     - `buildOverworldDecor(encountersList)` y `drawOverworld(ctx)` con Y-sorting limpio de props + Pudú + rivales, funcionando perfecto tanto con sprites reales (Modo A) como con placeholders greybox (Modo B).
     - `drawOverworldMinimap(puduU, puduV, encountersList, defeatedMap, w, h, font)` (`212x122` en `x=14, y=54`).
     - `drawBattleTransition(progress, w, h)`: doble flash blanco (`0..0.16`), 10 persianas diagonales + rombo dorado cerrando (`0.12..0.50`) y abriendo (`0.50..1.00`).

### Integración en `main.lua` (Coordinador)
- Integra `Encounters`, `StageRenderer`, `AssetLoader.loadAll(Encounters.LIST)` y `Audio:playTrack("overworld", false)`.
- Arranca en `Game.mode = "explore"`, `puduU = 3.8`, `puduV = StageRenderer.pathCenterV(3.8)`, `puduFacingRow = 3` (NE `↗`), `stage:snapCameraToChunk(puduU, puduV)`.
- Implementa `updateExplore(dt)`: WASD/Flechas -> `screenVecToIso(dx, dy, 6.2)` -> slide por eje separado con `isWalkable` -> 8 direcciones de sprite -> `stage:updateExploreCamera` -> colisión con rival no derrotado (`dist < 1.75`) dispara `triggerEncounterTransition(idx)`.
- Implementa `updateTransition(dt)`: `"alert"` (`0.40s`, dibuja `!` blanco/rojo sobre el rival y reproduce `sfx_encounter_start`) -> `"to_battle"` (`1.05s`, cambia a `Game.mode = "battle"` en `p >= 0.50`) y `"to_explore"` (`0.72s`, regresa al mapa separando al Pudú a `eu - 2.6` si estaba encima del rival).
- En Fase 1, cuando `Game.mode == "battle"`, dibuja una escena separada limpia (placeholder de arena con Pudú a la izquierda `0.28w`, rival a la derecha `0.72w`, título del encuentro y aviso `[ESC / TAB] Volver al mapa`) lista para reemplazarse en Fase 2.
- Añade flags CLI (escapando `%-%-`): `--biome=(.+)`, `--transition-preview=(%d+%.?%d*)`, manteniendo `--mode`, `--encounter`, `--mock`, `--screenshot`, `--quit-after`.
- Mantén `[F5]` (hot-reload), `[Tab]` (entrar al rival más cercano o salir de batalla), `[Esc]` (salir de batalla) y una pequeña pastilla superior izquierda con nombre del bioma actual.

### Verificación CLI Obligatoria al Terminar
Ejecuta las 5 capturas y verifica exit code `0` sin errores en `stderr`:
1. `./run.sh --mode=explore --biome=bosque --mock --screenshot=screenshots/fase01_bosque.png --quit-after=1.5`
2. `./run.sh --mode=explore --biome=desierto --mock --screenshot=screenshots/fase01_desierto.png --quit-after=1.5`
3. `./run.sh --mode=explore --biome=costa --mock --screenshot=screenshots/fase01_costa.png --quit-after=1.5`
4. `./run.sh --mode=explore --biome=ciudad --mock --screenshot=screenshots/fase01_ciudad.png --quit-after=1.5`
5. `./run.sh --mode=explore --encounter=1 --transition-preview=0.35 --mock --screenshot=screenshots/fase01_transition.png --quit-after=1.5`
```

---

## 5. Prompts Individuales por Subagente (Opcional si el equipo divide tareas)

### Subagente A — `encounters.lua`
```markdown
Crea `encounters.lua` para Pudú Fantasy según `AGENTS.md`.
Debe incluir los 4 biomas (`bosque`, `desierto`, `costa`, `ciudad` cubriendo `u = 0..118`), los 8 `STAGE_THEMES` (`plaza`, `bosque`, `mirador`, `vereda`, `muelle`, `pantano`, `esquina`, `oficina`) y los 9 encuentros exactos (`nino_helado` en `u=10,v=0.2`; `mimo_muro` en `u=22,v=-2`; `puma_dramatico` en `u=34,v=1.6` con `isSheet=true, sheetCols=4, sheetRows=2`; `turista_selfie` en `u=48,v=-1.2`; `gato_guaton` en `u=60,v=1.8`; `gaviota_mafiosa` en `u=74,v=-1.4`; `piscina_barro` en `u=86,v=1.2`; `semaforo_rebelde` en `u=99,v=-0.8`; `fila_tramite` en `u=112,v=0.4`), además de helpers `getById`, `getByIndex`, `getBiomeAtU`, `getTheme`, `loadOverrides` y `saveOverrides`. No modifiques otros archivos.
```

### Subagente B — `stage_renderer.lua` (Módulo Overworld + Cámara + Minimapa + Transición)
```markdown
Crea `stage_renderer.lua` (parte Overworld) para Pudú Fantasy según `AGENTS.md`.
Implementa:
1. Proyección diagonal `↗`: `ISO_UX=62, ISO_UY=-31, ISO_VX=62, ISO_VY=31, ELEV_PX=26`, `WORLD_U_MIN=-2, WORLD_U_MAX=118`, `pathCenterV`, `getBiomeAt`, `getElevation` (con río/puente en Bosque, meseta Atacama, océano/muelle en Costa, acrópolis en Ciudad y 6 `SIDE_ALCOVES`), `getTerrainType`, `isWalkable`, `screenVecToIso` y `getBattleAnchors`.
2. Cámara calma por salas: `ROOM_SPACING=14`, `camZoom=0.72`, `camPanDuration=0.65`, `roomCenter`, `snapCameraToChunk`, `updateExploreCamera` (100% inmóvil dentro de la sala; paneo único `smoothstep` solo al cruzar `du > 7.4` o `dv > 5.4`), `isCameraPanning`.
3. Render Back-to-Front (`STEP=1.5`, `u` descendente, `v` ascendente) con `_drawTileSkirts`, `_drawWaterTile`, `drawSkyAndHorizon`, `buildOverworldDecor`, `drawOverworld` (Y-sort), `drawOverworldMinimap` (`212x122` en `14, 54`) y `drawBattleTransition` (doble flash + 10 persianas + rombo dorado).
Debe degradar limpiamente si faltan PNGs de tiles o props (Modo B). No modifiques `main.lua`.
```

---

## 6. Prompt para Astra (Design Review & Auditoría Visual de la Fase)

> **Adjunta a Astra**: `screenshots/fase01_bosque.png`, `screenshots/fase01_desierto.png`, `screenshots/fase01_costa.png`, `screenshots/fase01_ciudad.png` y `screenshots/fase01_transition.png`.

```markdown
Eres Astra, Directora de Arte y Diseño de Niveles de Pudú Fantasy. Audita las 5 capturas de la **Fase 1 (Overworld Diagonal ↗, 4 Biomas y Transición JRPG)**.

Evalúa con ojo crítico de producción:
1. **Lectura de la dirección del viaje (`↗`)**: ¿Se entiende en menos de 2 segundos que el jugador avanza de abajo-izquierda hacia arriba-derecha? ¿Ayudan el camino serpenteante, las flechas doradas y el minimapa?
2. **Contraste entre los 4 biomas y relieve 3D**: ¿Bosque, Atacama, Valparaíso y Ciudad se sienten mundos claramente distintos? ¿Las faldas de acantilado, el puente sobre el río, el muelle con pilotes y la alfombra roja de oficina se ven tridimensionales sin grietas entre tiles?
3. **Composición de cámara y escalas**: ¿El `camZoom = 0.72` da suficiente respiro para ver el entorno, props y el próximo rival sin saturar la pantalla ni tapar al Pudú detrás de árboles?
4. **Minimapa y Transición JRPG**: ¿El minimapa `212x122` se lee limpio sin chocar con ningún texto? En `fase01_transition.png`, ¿la transición de persianas diagonales + rombo dorado tiene impacto retro tipo Final Fantasy / Pokémon?
5. **Veredicto**: `APROBADO PARA FASE 2` o `AJUSTAR ANTES DE FASE 2` con una lista corta y accionable (máx. 4 puntos).
```

---

## 7. Gate de Iteración en Equipo (Playtest de 5 min + Definition of Done)

### Guion de Playtest Manual (5 minutos)
1. **Minuto 0–1 (Sensación de cámara y movimiento)**: Arranca `./run.sh`, camina en círculos dentro de la primera sala del Bosque. Verifica que **la cámara NO tiembla ni persigue cada micro-paso**; el Pudú camina libremente dentro del encuadre.
2. **Minuto 1–2 (Cruce de sala y colisiones)**: Avanza hacia arriba-derecha (`W + D`) hasta cruzar el borde de la sala. Verifica que la cámara haga **un único paneo suave de ~0.65s**. Choca contra el borde del río (fuera del puente) y contra una pared de acantilado: el Pudú debe deslizarse suavemente sin quedarse trabado.
3. **Minuto 2–3 (Encuentro JRPG)**: Camina hacia el *Niño del Helado Triple* (`u=10, v=0.2`). Al tocarlo (`dist < 1.75`), confirma: alerta `!` (`0.4s`) -> sonido -> transición de flash + persianas -> aparición en escenario separado de batalla. Presiona `Esc` para regresar al overworld sin volver a disparar el combate en loop infinito.
4. **Minuto 3–5 (Recorrido por los 4 biomas)**: Usa `--biome=desierto`, `--biome=costa` y `--biome=ciudad` (o camina todo el trayecto) para validar puente, meseta de Atacama, muelle sobre agua y alfombra roja de la Oficina.

### Checklist de Definition of Done (DoD)
- [ ] Los 4 biomas renderizan completos sin vacíos negros en los bordes ni grietas entre tiles isométricos.
- [ ] Todos los 9 encuentros aparecen en su coordenada `(u, v)` y son alcanzables caminando (ninguno bloqueado por acantilado o agua).
- [ ] La cámara permanece **100% quieta** dentro de cada sala y panea suavemente solo al cambiar de sala (`du > 7.4` o `dv > 5.4`).
- [ ] El minimapa diagonal `↗` refleja en vivo la posición del Pudú y los 9 rivales.
- [ ] Colisionar con un rival dispara `!` -> transición JRPG -> cambio a `mode = "battle"`, y `Esc` retorna al overworld a distancia segura (`eu - 2.6`).
- [ ] Las 5 capturas CLI pasan con exit code `0` y aprobación de Astra.

### Comandos Exactos de Verificación
```bash
./run.sh --mode=explore --biome=bosque   --mock --screenshot=screenshots/fase01_bosque.png     --quit-after=1.5
./run.sh --mode=explore --biome=desierto --mock --screenshot=screenshots/fase01_desierto.png   --quit-after=1.5
./run.sh --mode=explore --biome=costa    --mock --screenshot=screenshots/fase01_costa.png      --quit-after=1.5
./run.sh --mode=explore --biome=ciudad   --mock --screenshot=screenshots/fase01_ciudad.png     --quit-after=1.5
./run.sh --mode=explore --encounter=1 --transition-preview=0.35 --mock --screenshot=screenshots/fase01_transition.png --quit-after=1.5
```

### Prompts Cortos de Ajuste Rápido (si algo no se siente bien)
- **Si el Pudú se traba al cruzar el puente o entrar a un claro de rival**:
  > *"En `stage_renderer.lua`, amplía ligeramente `isBosqueBridge` (`|v - pc| <= 2.45`) y el radio de `encounterClearingFactor` en `isWalkable` para que ningún rival quede detrás de una celda no caminable. Re-verifica los 9 encuentros."*
- **Si algún árbol/prop tapa al Pudú justo en el camino**:
  > *"En `StageRenderer:buildOverworldDecor`, sube el margen mínimo desde el centro del camino (`math.abs(pv - pathCenterV(pu)) >= 3.4`) y la distancia mínima a encuentros (`isTooCloseToEncounter(pu, pv, 3.6)`)."*
- **Si el paneo de cámara se siente brusco o demasiado frecuente**:
  > *"En `stage_renderer.lua`, verifica que `updateExploreCamera` use exactamente `du > 7.4 or dv > 5.4`, `camPanDuration = 0.65` y `smoothstep(self.camPanT)`, y que `main.lua` no mueva al Pudú mientras `stage:isCameraPanning()` sea `true`."*
