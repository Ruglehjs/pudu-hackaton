# FASE 03 — Motor IA de Prompts, Catálogo de 9 Rivales y Sistema de Combos en 2 Turnos

| Campo | Detalle |
| :--- | :--- |
| **Fase** | `FASE 03` — Cerebro IA de Batalla (2 Etapas + Especulativo), 9 Encuentros, 14 Gags Instantáneos, 8 Estados y 6 Super-Combos |
| **Duración estimada (Hackathon)** | **2.5 – 3.5 horas** (en paralelo con 3 subagentes de Codex + revisión creativa de Astra) |
| **Prerrequisitos (Gate de entrada)** | - **Fase 01 y Fase 02 completadas**: LÖVE2D 11.5 arranca sin errores, loop Overworld <-> Arena de Batalla operativo, `stage_renderer.lua` dibuja Pudú + rival, `json.lua` funcional y `audio.lua` carga SFX base.<br>- Python 3.10+ disponible (con `Pillow` y `numpy` si se activan sprites en vivo) y opcionalmente `gcloud` ADC o `GEMINI_API_KEY` en `.env`. |
| **Entregables concretos** | 1. `encounters.lua` (9 rivales en 3 categorías + 4 biomas + 8 `STAGE_THEMES` + `introLine` + `semiHintLine` + I/O de `stage_overrides.json`).<br>2. `ai_bridge.py` (servidor HTTP local `127.0.0.1:18425` con Stage 1 `global/gemini-2.5-flash` `thinkingBudget: 0`, schema estricto de 34 campos, Stage 2 especulativo `global/gemini-2.5-flash-image` + recorte chroma `#FF00FF` + normal map Sobel `_n.png` + cache RAM 12-slot LRU y disco `cache/sprites/`).<br>3. `battle_worker.lua` y `sprite_worker.lua` (hilos LÖVE2D no-bloqueantes + **motor standalone offline en Lua** con paridad total de 9 rivales, 8 estados y 6 combos).<br>4. Suite de pruebas automatizadas (`tests/test_ai_bridge.py` + test de fuzzing/combos + test offline Lua) y verificación de integración con `main.lua`. |

---

## 1. Objetivo de Producción y Alcance (Qué SÍ y Qué NO hacer en esta fase)

El objetivo de la **Fase 03** es darle a **Pudú Fantasy** su corazón único: un **Juez de Comedia RPG con física cómica ("Yes, And...")**, capaz de entender cualquier cosa absurda que escriba el jugador en español chileno/latino, devolver una respuesta estructurada y veloz en `<900 ms`, encadenar **estados físicos de escenario + super-combos en 2 turnos**, y generar sprites HD-2D en vivo (con normal map `_n.png`) en paralelo — **sin bloquear jamás el framerate de LÖVE2D y con respaldo 100% offline en Lua** para sobrevivir a caídas de WiFi o cuota en plena hackathon.

### Qué SÍ construir en esta fase

1. **Catálogo de 9 Encuentros Cómicos (`encounters.lua`)** distribuidos en 3 categorías (3 Personas, 3 Animales, 3 Desafíos) y 4 biomas chilenos (`bosque`, `desierto`, `costa`, `ciudad`):
   - Cada rival define: `id`, `index`, `biome`, `category`, `stage`, `music`, `sprite`, `u`/`v`, `maxHp`, `name`, `subtitle`, `situation`, `introLine` (diálogo inicial chistoso), `semiHintLine` (semi-pista sutil NO obvia que Fase 04 solo mostrará tras 2 fallos seguidos), `tauntLines`, `defeatLine`, `weaknesses`, `scale`/`offsetX`/`offsetY`.

| # | ID | Rival | Categoría | Bioma / Stage | HP | `introLine` (Inicio) | `semiHintLine` (Solo tras 2 fallos) |
| :-: | :--- | :--- | :--- | :--- | :-: | :--- | :--- |
| 1 | `nino_helado` | Niño del Helado Triple | `persona` | `bosque` / `plaza` | 100 | *"¡Jajá! Mi helado triple es más grande que tú, ciervito. ¡No pasas!"* | *"¡Qué suerte que hoy no hay ni una nube! Nada arruinaría más mi helado triple que el agua o un ladrón emplumado..."* |
| 2 | `mimo_muro` | Mimo del Muro Invisible | `persona` | `bosque` / `plaza` | 110 | *"...*toca el aire con desprecio y te hace cara de pared*..."* | *"*Hace señas orgullosas: nadie puede ver su muro invisible... y nada lo haría gritar salvo manchar su traje o un bicho real*"* |
| 3 | `puma_dramatico` | Puma Dramático | `animal` | `bosque` / `bosque` | 120 | *"¡Tiembla, pequeño pudú! Nadie arruinará mi entrada triunfal... ni mi pelaje."* | *"¡Mi melena es perfecta y mi porte feroz! Lástima que odio ensuciarme o ver cosas verdes largas de sorpresa..."* |
| 4 | `turista_selfie` | Turista del Selfie Infinito | `persona` | `desierto` / `mirador` | 105 | *"¡Un segundo! ¡No arruines mi foto para 12 seguidores!"* | *"¡Necesito cielo despejado y el lente limpio para mi mejor toma! ¡Solo el mal clima o algo que tape mi cámara me detendría!"* |
| 5 | `gato_guaton` | Gato Guatón Inamovible | `animal` | `desierto` / `vereda` | 110 | *"Mrrr... ni lo intentes. Aquí me quedo hasta el próximo martes."* | *"Mrrr... nada me mueve de esta siesta, salvo quizás un olor delicioso, una caja cómoda o un susto verde inesperado..."* |
| 6 | `gaviota_mafiosa` | Gaviota Mafiosa | `animal` | `costa` / `muelle` | 115 | *"¡KRA! Impuesto portuario, peludito: paga el peaje del muelle o no pasas."* | *"¡Kra! Mientras no me distraigan con algo rico del puerto ni me mojen los lentes oscuros, nadie cruza el muelle."* |
| 7 | `piscina_barro` | Pantano Traicionero | `desafio` | `costa` / `pantano` | 120 | *"¡Blub-blub! Ven a mojarte las patitas, tengo hambre de botas..."* | *"¡Blub! Mientras siga bien blandito y pegajoso, nadie cruza sin algo firme por encima o que cambie mi estado..."* |
| 8 | `semaforo_rebelde` | Semáforo Rebelde | `desafio` | `ciudad` / `esquina` | 120 | *"¡ROJO! ¡Y SI ME MIRAS FEO, LO PONGO MÁS ROJO AÚN!"* | *"¡ROJO ETERNO! Solo dejaría pasar si me cambiaran el color a la fuerza o me saltaran por arriba, ¡ja!"* |
| 9 | `fila_tramite` | Tótem de la Fila #999 | `desafio` | `ciudad` / `oficina` | 130 | *"¡Atendiendo al 004! Tú eres el 999... ¡Y te falta la fotocopia del timbre!"* | *"¡Aquí manda el papel y el orden! Solo un pase muy importante o algo que acabe con tanto formulario me vencería..."* |

2. **Puente IA de 2 Etapas + Lanzamiento Especulativo (`ai_bridge.py` en `127.0.0.1:18425`)**:
   - **Doble autenticación sin fricción**: soporta Google Cloud Vertex AI vía `gcloud` ADC (`global/gemini-2.5-flash` + `global/gemini-2.5-flash-image`) **Y** Gemini Developer API vía `GEMINI_API_KEY` (leído de `.env` o variable de entorno). Incluye pool thread-safe de sockets HTTPS keep-alive pre-calentados (`_HTTPSPool`) para evitar bloqueos TLS.
   - **Endpoints**: `GET /health`, `POST /battle_prompt`, `POST /sprite`.
   - **Stage 1 — Juez Cómico Ultrarrápido (`POST /battle_prompt`)**:
     - Modelo `global/gemini-2.5-flash` con `thinkingConfig: {"thinkingBudget": 0}`, `temperature: 0.55`, `maxOutputTokens: 850`, `responseMimeType: "application/json"` y `responseSchema` estricto de **34 campos obligatorios**:
       - *Validación e identidad*: `approved`, `reject_reason`, `summon_name` (<=34), `sprite_mode` (`generate_live` | `existing`), `existing_sprite`, `sprite_prompt` (inglés 10–16 palabras, *"facing right"*), `keep_purple`.
       - *Presentación y audio*: `delivery_style` (`overhead_weather`, `drop_from_sky`, `throw_arc`, `charge_across`, `pop_underneath`, `buff_pudu`), `particle_fx` (16 tipos), `sfx` (15 tipos), `reaction_sfx` (11 tipos), `keep_prop_on_stage`, `prop_anchor` (`above_enemy`, `ground_enemy`, `center`, `near_pudu`), `ritual_theme_color` (`#RRGGBB`).
       - *Juicio, daño y reacciones*: `outcome_type` (`super_funny_ko`, `effective`, `creative_chaos`, `backfire`, `heal_pudu`), `is_critical`, `damage_to_enemy` (0..100), `damage_to_pudu` (0..25), `heal_pudu` (0..35), `enemy_reaction` (15 estados: `idle`, `crying`, `laughing`, `angry`, `scared`, `shocked`, `distracted`, `wet`, `frozen`, `dizzy`, `embarrassed`, `happy_pacified`, `chased`, `splatted`, `confused`), `pudu_reaction` (`happy`, `smug`, `shocked`, `angry`, `dancing`), `enemy_speech` (<=72), `narrator_text` (<=78), `comedy_score` (1..10), `comedy_badge` (<=24), `status_tag` (<=14 MAYÚSCULAS).
       - *Contraataque rival*: `enemy_counter_name` (<=34), `enemy_counter_line` (<=72), `enemy_counter_damage` (5..22), `enemy_counter_fx` (9 tipos).
       - *Estados, combos y anticipación*: `adds_stage_state`, `combo_triggered`, `combo_name` (<=34 MAYÚSCULAS), `anticipation_line` (<=52).
     - **Filosofía "Yes, And..."**: un prompt creativo pero no relacionado (ej. `"silla"` al Niño del Helado) NUNCA dice *"no funcionó"*; improvisa un mini-gag (`creative_chaos`, 20–40 daño, `is_critical=false`). Solo se rechaza (`approved=false`) ante meta-trampas (`"ganar"`, `"modo dios"`, `"hack"`), teclado roto (`"asdfgh"`) o saludos vacíos (`"hola"`).
     - **Sanitizador determinista (`sanitize_battle_result`)**: valida los 34 tipos, recorta longitudes con elipsis limpia, y fuerza invariantes (si `combo_triggered != "none"` => `is_critical=True`, `outcome_type="super_funny_ko"`, `damage_to_enemy >= 90`, `comedy_score=10`).
   - **8 Estados de Escenario (`adds_stage_state`)**: `mojado`, `congelado`, `aceitoso`, `enjabonado`, `oscuro`, `ruidoso`, `caliente`, `pegajoso` (más `"none"`). Se acumulan hasta 3 simultáneos por combate en `Game.stageStates` y se envían al juez en el siguiente turno.
   - **6 Super-Combos en 2 Turnos (`combo_triggered`)**:

| `combo_triggered` | Condición de 2 turnos (Estado previo + Turno actual) | `combo_name` | Daño mín. | Reacción / Sprite |
| :--- | :--- | :--- | :-: | :--- |
| `combo_electro` | `mojado` (o prop agua/rival `wet`) + rayo/electricidad/tostadora/batería/anguila | `¡COMBO ELECTRO-CHARCO!` | 96 | `shocked` / `lightning_bolt` |
| `combo_deep_freeze` | `mojado` + hielo/nieve/ventisca/ventilador/pingüino | `¡COMBO CUBO DE HIELO!` | 95 | `frozen` |
| `combo_steam_sauna` | (`mojado` o `congelado`) + fuego/sol/secador/lava **ó** `caliente` + agua/hielo | `¡COMBO SAUNA VAPOR!` | 92 | `dizzy` |
| `combo_slip_slide` | (`mojado`, `enjabonado` o `aceitoso`) + jabón/plátano/viento/ventilador | `¡COMBO RESBALÓN TURBO!` | 92 | `dizzy` |
| `combo_fire_boom` | (`aceitoso`, `pegajoso` o papel de `fila_tramite`) + fuego/fósforo/bomba/dragón | `¡COMBO EXPLOSIÓN!` | 96 | `shocked` |
| `combo_chaos` | `oscuro` + susto/bocina/flash **ó** `ruidoso` + yunque/bomba/bocina | `¡COMBO CAOS TOTAL!` | 92 | `scared` o `dizzy` |

   - **Stage 2 Inteligente + Lanzamiento Especulativo (`POST /sprite`)**:
     - **Fast-path instantáneo (`<0.8s`) para los 14 sprites gag pre-cacheados**: `rain_cloud`, `banana_peel`, `cucumber`, `melted_icecream`, `lightning_bolt`, `hair_dryer`, `giant_fan`, `paint_bucket`, `empanada`, `cardboard_box`, `robot_vacuum`, `giant_anvil`, `soap_bubbles`, `vip_stamp` (más props existentes como `wooden_bridge`, `crystal_mirror` y fauna `fauna_dog`..`fauna_flamingo`). Si `_canonical_sprite_key(prompt)` (quitando verbos/artículos como *"invoca una"*) hace match exacto, **NO dispara generación de imagen**.
     - **Speculative Launch en `t=0ms` para prompts locos/nuevos** (ej. *"ornitorrinco dj"*, *"tostadora espacial"*): apenas entra `POST /battle_prompt`, `maybe_start_speculative_sprite()` lanza en paralelo `global/gemini-2.5-flash-image` en un `ThreadPoolExecutor(max_workers=3)` con referencia de estilo `128x128` (`pudu_hero.png` sobre magenta `#FF00FF`). Cuando termina Stage 1, `bind_speculative_alias()` enlaza `summon_name` al `Future` ya en vuelo.
     - **Post-proceso pixel-art HD-2D**: remoción chroma magenta `#FF00FF` (`keep_purple` protege morados como berenjena/pulpo) + BFS flood-fill desde bordes (`_clean_corner_bg_floodfill`) + recorte/centrado (`target_max_dim=76..80`, `anchor_bottom=True`) + generación automática de **normal map Sobel `_n.png`** (`strength=2.4`, `dome_weight=0.45`).
     - **Doble caché**: LRU en RAM de 12 slots (`OrderedDict`) + persistencia en disco en `cache/sprites/<slug>_<sha1>.png` y `_n.png`.

3. **Hilos No-Bloqueantes + Motor Offline Standalone en Lua (`battle_worker.lua`, `sprite_worker.lua`)**:
   - `battle_worker.lua` escucha canal `battle_in` (`health`, `prompt`, `quit`) y responde por `battle_out` (`health`, `prompt_result`). Si `ai_bridge.py` no responde (sin WiFi, sin Python o HTTP != 200), cae de forma silenciosa y transparente a `standaloneLuaEvaluate()` con **paridad completa de los 9 rivales, rechazos, backfires, curas, 8 estados y 6 combos**.
   - `sprite_worker.lua` escucha `sprite_in` (`generate`, `quit`), llama `POST /sprite` (timeout 28s) y devuelve `diff_b64` + `norm_b64` por `sprite_out` para que `main.lua` los decodifique en texturas `nearest` sin congelar el hilo principal.

### Qué NO hacer en esta fase

- **NO** implementar todavía el ritual visual de flechas, animaciones de orbe, anticipación dibujada ni la UI final del HUD (eso es exclusivo de **Fase 04**).
- **NO** programar el espectáculo de partículas 3D/combo FX ni finales de derrota complejos (basta exponer el resultado JSON limpio y los hooks en `main.lua`; los VFX cinematográficos van en Fase 05).
- **NO** bloquear `love.update()` con llamadas HTTP síncronas (`socket.http` **solo** vive dentro de `battle_worker.lua` y `sprite_worker.lua`).
- **NO** mostrar botones de pistas o spoilers de `weaknesses` al usuario; `weaknesses` existe solo como contexto interno para el juez IA y el motor offline.

---

## 2. Modo Assets: ¿Ya tengo sprites/música o los incorporo después?

Esta fase está diseñada para funcionar en **ambos modos** sin detener al equipo ni un minuto:

| Modo | Situación del equipo | Cómo operar en Fase 03 |
| :--- | :--- | :--- |
| **Modo A — Assets ya listos** | Ya tienes los 14 pares `.png` + `_n.png` en `assets/sprites/gags/` y los 9 sprites en `assets/sprites/encounters/` + `assets/sprites/pudu_hero.png`. | `ai_bridge.py` usa `pudu_hero.png` como referencia `128x128` para igualar el estilo pixel-art HD-2D de los sprites en vivo; `main.lua` resuelve los 14 gags instantáneos desde `assets/sprites/gags/<id>.png` + `_n.png`. |
| **Modo B — Sin assets todavía (Placeholder-first)** | El artista o el generador batch aún está produciendo los sprites finales de gags/rivales. | 1. Corre un mini-script o usa un fallback de textura procedural (`64x64` con normal map plano `#8080FF`) cuando falte algún PNG en `assets/sprites/gags/`.<br>2. Mantén los 14 IDs canónicos exactos (`rain_cloud` .. `vip_stamp`) en `EXISTING_SPRITE_KEYWORDS` y `resolveExistingSummonSprite()` para que al soltar los PNG finales (y presionar `[F5]` hot-reload) todo enganche sin tocar una línea de lógica.<br>3. Si `pudu_hero.png` aún no existe, `ai_bridge.py` igual genera sprites live sin `inlineData` de referencia (solo con la instrucción textual 16-bit HD-2D + `#FF00FF`). |

> **Regla de Oro de Normal Maps**: cada sprite nuevo (tanto pre-cacheado como generado en vivo en Stage 2) viaja en pareja `{ diff, norm }` (`.png` + `_n.png`). Si un sprite placeholder no tiene `_n.png`, el loader devuelve `norm = nil` de forma segura sin crashear el shader de iluminación.

---

## 3. División Codex vs Astra + Subagentes de esta Fase

Para maximizar velocidad en hackathon sin conflictos de merge, cada rol tiene propiedad exclusiva de sus archivos:

| Rol | Herramienta | Propiedad exclusiva de archivos | Responsabilidad principal |
| :--- | :--- | :--- | :--- |
| **Orquestador Principal** | **Codex (Lead)** | `main.lua` (solo hooks de workers/estado `stageStates`/`pollWorkers`), integración final y runners CLI | Conecta canales `battle_in`/`battle_out` y `sprite_in`/`sprite_out`, valida contrato JSON de 34 campos y ejecuta suite de tests end-to-end. |
| **Subagente A — Catálogo & Datos** | **Codex Subagent** | `encounters.lua` | Define los 9 rivales (3 categorías, 4 biomas), 8 `STAGE_THEMES`, `introLine`, `semiHintLine` (sutil, cero spoilers obvios), `weaknesses` e I/O `stage_overrides.json`. |
| **Subagente B — Cerebro IA Python** | **Codex Subagent** | `ai_bridge.py`, `tools/sprite_studio.py` (o módulo chroma+Sobel), `tests/test_ai_bridge.py` | Implementa servidor puerto `18425`, `_HTTPSPool`, Stage 1 `gemini-2.5-flash` (`thinkingBudget: 0`, 34 campos), Stage 2 especulativo `gemini-2.5-flash-image`, chroma `#FF00FF`, normal map Sobel, 14 gags instantáneos y caché RAM+disco. |
| **Subagente C — Workers & Motor Offline Lua** | **Codex Subagent** | `battle_worker.lua`, `sprite_worker.lua`, `tests/test_offline_lua.lua` | Implementa hilos LÖVE2D no-bloqueantes, `ensureResultCoherence()` y el motor offline `standaloneLuaEvaluate()` con 100% paridad de 9 rivales, 8 estados y 6 combos. |
| **Design & Comedy Reviewer** | **Astra** | *(Solo lectura / reporte de revisión)* | Audita calidad del humor chileno/slapstick, verifica que `semiHintLine` sea sutil y no obvia, prueba 15+ prompts extremos (backfires, combos, absurdos "Yes, And...") y detecta fallos de ritmo o incoherencias cómicas. |

---

## 4. Prompt Maestro para Codex (Copiar y Pegar — Orquestación con Subagentes)

```text
Actúa como Tech Lead de Pudú Fantasy ejecutando la FASE 03 (Motor IA de Prompts, Catálogo de 9 Rivales y Sistema de Combos en 2 Turnos).

CONTEXTO TÉCNICO DEL PROYECTO:
- Motor: LÖVE2D 11.5 (LuaJIT) + puente HTTP local en Python (`127.0.0.1:18425`, env `PUDU_BATTLE_PORT`).
- Restricción estricta de arquitectura: ZERO llamadas HTTP bloqueantes en el hilo principal de LÖVE2D. Toda comunicación pasa por `love.thread` (`battle_in`/`battle_out`, `sprite_in`/`sprite_out`).
- Resiliencia de hackathon: el juego DEBE funcionar al 100% en 3 modos: (1) Vertex AI (`gcloud` ADC, `global/gemini-2.5-flash` + `global/gemini-2.5-flash-image`), (2) Gemini Developer API (`GEMINI_API_KEY` en `.env`), y (3) 100% Offline Standalone en Lua sin Python ni WiFi.

ORQUESTACIÓN EN PARALELO (lanza 3 subagentes con propiedad exclusiva de archivos):
1. Subagente A (`encounters.lua`):
   - Crea los 9 encuentros en 3 categorías (`persona`: `nino_helado`, `mimo_muro`, `turista_selfie`; `animal`: `puma_dramatico`, `gato_guaton`, `gaviota_mafiosa`; `desafio`: `piscina_barro`, `semaforo_rebelde`, `fila_tramite`) repartidos en 4 biomas (`bosque`, `desierto`, `costa`, `ciudad`) y 8 `STAGE_THEMES`.
   - Cada encuentro incluye `introLine` graciosa, `semiHintLine` SUTIL (jamás dice la palabra exacta de la solución directamente), `tauntLines`, `defeatLine`, `weaknesses`, y helpers `loadOverrides`/`saveOverrides` para `stage_overrides.json`.
2. Subagente B (`ai_bridge.py` + `tests/test_ai_bridge.py`):
   - Servidor `ThreadingHTTPServer` en `127.0.0.1:18425` con `GET /health`, `POST /battle_prompt`, `POST /sprite`.
   - Stage 1: `global/gemini-2.5-flash` con `thinkingConfig: {"thinkingBudget": 0}`, `temperature: 0.55`, `responseMimeType: "application/json"`, `responseSchema` estricto de 34 campos obligatorios (`approved`, `reject_reason`, `summon_name`, `sprite_mode`, `existing_sprite`, `sprite_prompt`, `keep_purple`, `delivery_style`, `particle_fx`, `sfx`, `reaction_sfx`, `outcome_type`, `is_critical`, `damage_to_enemy`, `damage_to_pudu`, `heal_pudu`, `enemy_reaction`, `pudu_reaction`, `enemy_speech`, `narrator_text`, `enemy_counter_name`, `enemy_counter_line`, `enemy_counter_damage`, `enemy_counter_fx`, `comedy_score`, `comedy_badge`, `keep_prop_on_stage`, `prop_anchor`, `status_tag`, `ritual_theme_color`, `adds_stage_state`, `combo_triggered`, `combo_name`, `anticipation_line`).
   - 8 `adds_stage_state`: `mojado`, `congelado`, `aceitoso`, `enjabonado`, `oscuro`, `ruidoso`, `caliente`, `pegajoso` (+ `none`).
   - 6 `combo_triggered`: `combo_electro`, `combo_deep_freeze`, `combo_steam_sauna`, `combo_slip_slide`, `combo_fire_boom`, `combo_chaos` (+ `none`).
   - 14 gags pre-cacheados instantáneos (`rain_cloud`, `banana_peel`, `cucumber`, `melted_icecream`, `lightning_bolt`, `hair_dryer`, `giant_fan`, `paint_bucket`, `empanada`, `cardboard_box`, `robot_vacuum`, `giant_anvil`, `soap_bubbles`, `vip_stamp`) mapeados en `EXISTING_SPRITE_KEYWORDS` + `match_exact_existing_sprite()` para saltar generación de imagen cuando hay match canónico exacto.
   - Stage 2 especulativo: para prompts nuevos/locos lanza `maybe_start_speculative_sprite()` en paralelo con Stage 1 (`ThreadPoolExecutor`), usa `global/gemini-2.5-flash-image` con ref 128x128 de `pudu_hero.png` sobre `#FF00FF`, aplica recorte chroma magenta (`keep_purple` para objetos morados) + BFS flood-fill de bordes + normal map Sobel (`_n.png`), guarda en caché RAM LRU (12 slots) y disco (`cache/sprites/`), y enlaza alias con `bind_speculative_alias()`.
   - Incluye `fallback_battle_evaluate()` en Python para modo `--mock` o error de API, más `sanitize_battle_result()` garantizando todas las invariantes de los 34 campos.
3. Subagente C (`battle_worker.lua`, `sprite_worker.lua`, `tests/test_offline_lua.lua`):
   - `battle_worker.lua`: hilo LÖVE2D con HTTP timeout 15s, `ensureResultCoherence()` y motor offline completo `standaloneLuaEvaluate()` que replica los 9 rivales, backfires, curas, rechazos, 8 estados, 6 combos y catch-all "Yes, And...".
   - `sprite_worker.lua`: hilo LÖVE2D con HTTP timeout 28s que llama `POST /sprite` y retorna `diff_b64` + `norm_b64`.

INTEGRACIÓN EN `main.lua` (Lead):
- Arranca ambos hilos en `love.load()`, envía `{ cmd = "health" }`, despacha prompts incluyendo `stage_states` y `active_props`, actualiza `Game.stageStates` (máx. 3 activos) y decodifica `diff_b64`/`norm_b64` a `love.graphics.newImage` con filtro `nearest`.
- Agrega flags CLI de prueba: `--mock`, `--mode=battle`, `--encounter=<1..9>`, `--auto-prompt="<texto>"`, `--demo-combo=<combo_id>`, `--screenshot=<ruta>`, `--quit-after=<seg>`.

VERIFICACIÓN OBLIGATORIA ANTES DE TERMINAR (ejecuta todo y muéstrame los resultados):
1. Tests unitarios y fuzzing Python (`python3 -m unittest tests/test_ai_bridge.py`):
   - Validar los 34 campos, longitudes máximas y enums con 30+ prompts (críticos por cada uno de los 9 rivales, backfires, curas, meta-cheats, gibberish `"asdfgh"`, saludos `"hola"`, acentos/UTF-8, y prompts absurdos "Yes, And...").
   - Validar los 6 super-combos en 2 turnos (verificar `is_critical == True`, `damage_to_enemy >= 90`, `combo_triggered` exacto).
   - Validar que los 14 gags pre-cacheados devuelven `sprite_mode == "existing"` sin disparar Stage 2 cloud, mientras `"ornitorrinco dj"` dispara ruta especulativa `generate_live`.
2. Test de paridad offline en Lua (`luajit tests/test_offline_lua.lua` o runner con mocks de `love.thread`):
   - Verificar que con `ai_bridge.py` APAGADO los 9 rivales + 6 combos + 8 estados + rechazos responden con las 34 llaves válidas.
3. Prueba HTTP en vivo + Captura CLI en LÖVE2D:
   - Levanta `ai_bridge.py`, verifica `curl -s http://127.0.0.1:18425/health`, envía un `POST /battle_prompt` en modo `mock_mode: true` y otro en vivo (si hay credenciales).
   - Ejecuta LÖVE2D en headless/CLI con `--mode=battle --encounter=1 --mock --auto-prompt="nube de lluvia" --screenshot=screenshots/fase03_lluvia_test.png --quit-after=6.5` y con `--mode=battle --encounter=1 --demo-combo=combo_electro --screenshot=screenshots/fase03_combo_electro.png --quit-after=2.5`.
   - Confirma cero errores en `stderr` y adjunta resumen de latencias y pruebas pasadas.
```

---

## 5. Prompts Individuales por Subagente

Usa estos prompts si prefieres lanzar cada subagente por separado o relanzar una pieza puntual sin tocar las demás.

### Subagente A — Catálogo de 9 Rivales y Biomas (`encounters.lua`)

```text
Crea únicamente `encounters.lua` (sin tocar `main.lua` ni `ai_bridge.py`).

REQUISITOS EXACTOS:
1. Define 4 biomas (`bosque`, `desierto`, `costa`, `ciudad`) y 8 `STAGE_THEMES` (`plaza`, `bosque`, `mirador`, `vereda`, `muelle`, `pantano`, `esquina`, `oficina`) con paletas de cielo, suelo, camino, luz solar normalizada y props.
2. Define exactamente 9 encuentros en `Encounters.LIST` cubriendo 3 categorías:
   - `persona`: `nino_helado`, `mimo_muro`, `turista_selfie`
   - `animal`: `puma_dramatico` (spritesheet 4x2), `gato_guaton`, `gaviota_mafiosa`
   - `desafio`: `piscina_barro`, `semaforo_rebelde`, `fila_tramite`
3. Cada encuentro DEBE tener:
   - `introLine`: diálogo inicial chistoso en español chileno/latino (<=90 chars).
   - `semiHintLine`: semi-pista sutil en personaje, divertida y NO obvia (sin escribir comandos literales tipo "escribe lluvia"), diseñada para mostrarse SOLO tras 2 fallos seguidos.
   - `tauntLines` (4 frases), `defeatLine`, `weaknesses` (palabras clave sin acentos para el juez IA/offline), `maxHp` (100–130), `scale`, `offsetX`, `offsetY`.
4. Expón helpers `count()`, `getById(id)`, `getByIndex(idx)`, `getTheme(stageId)`, `getBiome(biomeId)`, `getBiomeAtU(u)`, `getEncountersInBiome(biomeId)`, y persistencia `loadOverrides(jsonMod)` / `saveOverrides(jsonMod, overrides)` para `stage_overrides.json` compatible con modo unfused y fused.
5. Verifica sintaxis ejecutando `luajit -e 'local E=require("encounters"); assert(E.count()==9); for _,e in ipairs(E.LIST) do assert(e.introLine and e.semiHintLine and #e.weaknesses>=5) end; print("OK 9 encounters")'`.
```

### Subagente B — Puente IA 2 Etapas + Especulativo (`ai_bridge.py` + `tests/test_ai_bridge.py`)

```text
Crea `ai_bridge.py` y `tests/test_ai_bridge.py` (sin modificar archivos `.lua`).

REQUISITOS DE ARQUITECTURA:
1. Puerto local `127.0.0.1:18425` (configurable con `PUDU_BATTLE_PORT`), `ReusableThreadingHTTPServer` con `daemon_threads = True`, y carga automática de `.env` sin sobrescribir variables existentes ni imprimir secretos.
2. Pool HTTPS persistente thread-safe (`_HTTPSPool`) sin mantener locks durante I/O de red, con `warmup()` al inicio. Soporta Vertex AI vía `gcloud` ADC (`global/gemini-2.5-flash` y `global/gemini-2.5-flash-image`) y fallback a Gemini Developer API (`GEMINI_API_KEY`).
3. Stage 1 (`POST /battle_prompt`):
   - Prompt de sistema "Juez de Comedia RPG" con filosofía "Yes, And...", calibración de críticos (`is_critical`, 85..100 dmg), parciales (`effective`, 42..56), mini-gags (`creative_chaos`, 20..40), `backfire` (0..5 dmg enemigo, 10..18 dmg pudú), `heal_pudu` (18..32 cura), y rechazo SOLO para meta-cheats/gibberish/saludos vacíos.
   - `generationConfig` con `thinkingConfig: {"thinkingBudget": 0}`, `temperature: 0.55`, `responseMimeType: "application/json"`, `responseSchema` con exactamente las 34 propiedades requeridas.
   - Función `sanitize_battle_result(raw, prompt, encounter)` que valida los 34 campos, enums, clamps, límites de caracteres (`enemy_speech<=72`, `narrator_text<=78`, `anticipation_line<=52`, `combo_name<=34`, `status_tag<=14`) y las invariantes de los 6 combos (`combo_electro`, `combo_deep_freeze`, `combo_steam_sauna`, `combo_slip_slide`, `combo_fire_boom`, `combo_chaos`) y 8 estados (`mojado`, `congelado`, `aceitoso`, `enjabonado`, `oscuro`, `ruidoso`, `caliente`, `pegajoso`).
4. Stage 2 inteligente y especulativo (`POST /sprite`):
   - Mapeo exacto canónico `EXISTING_SPRITE_KEYWORDS` para los 14 gags pre-cacheados (`rain_cloud`, `banana_peel`, `cucumber`, `melted_icecream`, `lightning_bolt`, `hair_dryer`, `giant_fan`, `paint_bucket`, `empanada`, `cardboard_box`, `robot_vacuum`, `giant_anvil`, `soap_bubbles`, `vip_stamp`) + props/fauna existentes. Si hace match exacto, NO invoca generación de imagen en la nube.
   - Para prompts nuevos/creativos, `maybe_start_speculative_sprite(prompt)` dispara en paralelo la generación con `global/gemini-2.5-flash-image` usando ref `128x128` de `assets/sprites/pudu_hero.png` sobre `#FF00FF`, luego aplica chroma key magenta (`keep_purple` para palabras como berenjena/pulpo/uva), BFS flood-fill desde bordes (`_clean_corner_bg_floodfill`), trim/pad (`target_max_dim=76..80`, `anchor_bottom=True`) y normal map Sobel (`_n.png`).
   - Caché RAM LRU de 12 slots (`OrderedDict`) + caché persistente en disco en `cache/sprites/`.
5. Incluye motor local `fallback_battle_evaluate(prompt, encounter)` para `mock_mode=True` o fallo de red.
6. Escribe `tests/test_ai_bridge.py` cubriendo: 34 campos, 9 rivales, 14 gags instantáneos, 8 estados, 6 combos, sanitización de JSON corrupto/extremo, fuzzing de prompts vacíos/gibberish/cheats/emojis/UTF-8, y verificación de skip especulativo vs lanzamiento live. Ejecuta los tests y verifica que pasen 100%.
```

### Subagente C — Hilos LÖVE2D y Motor Offline Standalone (`battle_worker.lua`, `sprite_worker.lua`)

```text
Crea `battle_worker.lua`, `sprite_worker.lua` y el test `tests/test_offline_lua.lua` (sin editar `ai_bridge.py` ni `encounters.lua`).

REQUISITOS EXACTOS:
1. `battle_worker.lua`:
   - Usa `socket.http`, `ltn12`, `json` y canales `battle_in` / `battle_out` con `http.TIMEOUT = 15` contra `http://127.0.0.1:<PUDU_BATTLE_PORT|18425>`.
   - Soporta comandos `health`, `prompt` y `quit`.
   - Implementa `ensureResultCoherence(res)` garantizando las invariantes de `is_critical`, `combo_triggered`, `adds_stage_state`, `anticipation_line` y longitudes UTF-8 seguras (`utf8Clip`).
   - Implementa `standaloneLuaEvaluate(rawPrompt, encounter)` como motor completo de respaldo cuando no hay respuesta HTTP 200:
     * Rechaza vacíos, gibberish, saludos y meta-cheats.
     * Detecta los 8 `adds_stage_state` y dispara los 6 super-combos en 2 turnos inspeccionando `encounter.stage_states`, `encounter.active_props` y `encounter.current_reaction`.
     * Cubre críticos y backfires específicos para TODOS los 9 rivales (`nino_helado`, `mimo_muro`, `puma_dramatico`, `turista_selfie`, `gato_guaton`, `gaviota_mafiosa`, `piscina_barro`, `semaforo_rebelde`, `fila_tramite`), curas (`heal_pudu`) y mini-gag catch-all "Yes, And..." (30 dmg, chistoso y nunca aburrido).
     * Resuelve sprites existentes incluyendo los 14 gags pre-cacheados.
   - Cuida el límite de 200 variables locales de LuaJIT empaquetando categorías semánticas y estados en tablas (`cat`, `st`).
2. `sprite_worker.lua`:
   - Hilo dedicado en canales `sprite_in` / `sprite_out` con `http.TIMEOUT = 28`.
   - Comando `generate` -> `POST /sprite` con `{ name, sprite_prompt, keep_purple, is_animal, target_dim }` -> empuja `{ kind="sprite_ready", uid, name, ok, cached, width, height, latency_ms, diff_b64, norm_b64, error }`.
3. Crea `tests/test_offline_lua.lua` que inyecta mocks mínimos de `love.thread` y prueba offline los 9 rivales, los 6 combos en 2 turnos, los 8 estados, backfires y rechazos. Ejecuta y confirma 100% pass sin superar el límite de locales de LuaJIT.
```

---

## 6. Prompt para Astra (Design Review de Humor, Prompts y UX Limpia)

Ejecuta esta revisión con **Astra** en cuanto los 3 subagentes hayan integrado el motor y pasado los tests unitarios:

```text
Actúa como Comedy Game Director y Narrative UX Auditor (Astra) revisando la FASE 03 de Pudú Fantasy.

Lee en modo solo-lectura `encounters.lua`, `ai_bridge.py` (`SYSTEM_INSTRUCTION`, `RESPONSE_SCHEMA`, `EXISTING_SPRITE_KEYWORDS`, `COMBO_DEFAULT_*`) y `battle_worker.lua` (`standaloneLuaEvaluate`).

AUDITA Y REPORTA CON VEREDICTO (APROBADO / AJUSTES MENORES / BLOQUEANTE) ESTOS 6 EJES:
1. **Humor físico y voz chilena/latina**:
   - ¿Todas las `introLine`, `enemy_speech` y `narrator_text` se leen en menos de 2 segundos y rematan con humor visual/slapstick (cero chistes largos ni tono corporativo de IA)?
   - Señala cualquier texto que supere 72 chars (`enemy_speech`) o 78 chars (`narrator_text`) o se sienta genérico.
2. **Calibración de `semiHintLine` (Anti-Spoiler)**:
   - Revisa las 9 `semiHintLine` en `encounters.lua`. ¿Alguna regala literalmente la palabra del prompt (ej. "tírame un pepino") en vez de dar una pista cómica sutil? Propón reescritura inmediata para cualquier pista demasiado obvia.
3. **Regla "Yes, And..." en prompts absurdos**:
   - Simula mentalmente o sobre el output de test 5 prompts raros contra el Niño del Helado y el Mimo (ej. `"licuadora"`, `"silla de plástico"`, `"ornitorrinco dj"`, `"calculadora"`, `"paraguas"`). ¿El juego premia el absurdo con risa + reacción física y castiga con humor los backfires?
4. **Descubrimiento natural de los 8 estados y 6 combos en 2 turnos**:
   - ¿El texto de turno 1 sugiere intuitivamente el estado físico dejado en escena (ej. piso mojado, enjabonado, aceitoso, a oscuras) para que al jugador se le ocurra rematar con rayo, hielo, fuego o plátano en el turno 2?
   - ¿Las `anticipation_line` de los 6 combos crean suspenso cómico antes del golpe?
5. **Paridad Online vs Offline**:
   - Compara `ai_bridge.py` con `battle_worker.lua`: si muere el WiFi durante la presentación de la hackathon, ¿algún rival se queda sin chiste, sin backfire o sin combo?
6. **Cobertura de los 14 gags instantáneos**:
   - ¿Los sinónimos en `EXISTING_SPRITE_KEYWORDS` cubren las formas naturales en que un jugador latino escribiría cada gag (con/sin tildes, diminutivos o artículos como "una empanada", "balde de pintura", "caja de carton") sin capturar por error prompts compuestos creativos como `"empanada ninja espacial"`?

Entrega una lista priorizada (máx. 8 mejoras concretas listas para copiar y pegar a Codex).
```

---

## 7. Gate de Iteración en Equipo (Playtest de 5 min + Definition of Done)

### Playtest relámpago de 5 minutos (5 prompts locos en vivo con el equipo)

Reúnan a todo el equipo frente a una pantalla (con `ai_bridge.py` encendido y luego 1 minuto con `ai_bridge.py` apagado para probar el fallback offline) y ejecuten estos **5 prompts en vivo**:

1. **Test Crítico + Gag Pre-cacheado (`<0.8s`)**: contra *Niño del Helado Triple*, escribir **`nube de lluvia`**.
   - *Esperado*: respuesta rápida sin llamada de generación de imagen, `is_critical=true`, daño >= 85, `enemy_reaction="crying"`, `adds_stage_state="mojado"`, risa inmediata en la mesa.
2. **Test Super-Combo en 2 Turnos**: contra *Gato Guatón* o *Turista Selfie*, Turno 1 **`balde de agua`** (deja `mojado`) -> Turno 2 **`tostadora`** o **`rayo`**.
   - *Esperado*: dispara `combo_electro` (`¡COMBO ELECTRO-CHARCO!`), daño >= 96, `anticipation_line` de pánico, `existing_sprite="lightning_bolt"`.
3. **Test Sprite en Vivo Especulativo + "Yes, And..."**: contra *Mimo del Muro*, escribir **`ornitorrinco dj`** o **`tostadora espacial`**.
   - *Esperado*: `sprite_mode="generate_live"`, el sprite llega recortado sin borde magenta + con normal map `_n.png`, y el juez arma un mini-gag genuinamente chistoso (sin decir *"no funcionó"*).
4. **Test Backfire (Autogol Cómico)**: contra *Niño del Helado Triple*, escribir **`paraguas`** (o **`muro de cemento`** contra el *Mimo*).
   - *Esperado*: `outcome_type="backfire"`, `enemy_reaction="laughing"`, el rival se burla y el Pudú recibe 10–18 de daño.
5. **Test Resiliencia + Anti-Trampa + Modo Offline**: escribir **`modo dios`** (debe ser rechazado con humor por el árbitro cósmico) y luego apagar `ai_bridge.py` y lanzar **`empanada`** contra *Gaviota Mafiosa* + combo **`jabón`** -> **`plátano`** (`combo_slip_slide`).
   - *Esperado*: cero crashes, cero cuelgues de FPS, 100% jugable sin internet.

### Definition of Done (Checklist de salida de Fase 03)

- [ ] `encounters.lua` carga los 9 encuentros (3 Personas, 3 Animales, 3 Desafíos) con `introLine` y `semiHintLine` sutil verificadas por Astra.
- [ ] `ai_bridge.py` escucha en `127.0.0.1:18425`, responde `/health` en `<50 ms` y `/battle_prompt` en `<1200 ms` (objetivo 650–900 ms con TLS caliente y `thinkingBudget: 0`).
- [ ] `sanitize_battle_result()` garantiza los 34 campos y pasa el 100% de `tests/test_ai_bridge.py` (incluyendo fuzzing).
- [ ] Los 14 gags pre-cacheados toman la ruta instantánea (`existing`) y los prompts creativos lanzan Stage 2 especulativo en paralelo con recorte `#FF00FF` + `_n.png` + caché RAM/disco.
- [ ] Los 8 estados de escenario persisten entre turnos y los 6 super-combos disparan daño crítico (>=90) tanto online (Gemini) como offline (`battle_worker.lua`).
- [ ] Apagar `ai_bridge.py` en medio de una partida NO congela ni crashea LÖVE2D; el jugador puede terminar la batalla en modo standalone Lua.
- [ ] Capturas CLI de verificación generadas sin errores en `stderr`.

### Prompts rápidos de iteración (si algo falla en el playtest)

- **Si un prompt loco queda con halo magenta en los bordes**:
  > *"Ajusta `remove_magenta_chroma` y `_clean_corner_bg_floodfill` en `ai_bridge.py` (aumenta `color_tol` de 52 a 60 y verifica que `keep_purple=True` solo relaje el umbral en prompts morados), limpia `cache/sprites/` y vuelve a probar con `'ornitorrinco dj'` y `'berenjena gigante'`."*
- **Si el juez IA es muy tacaño o demasiado generoso con los críticos**:
  > *"Calibra `SYSTEM_INSTRUCTION` y `sanitize_battle_result()` en `ai_bridge.py` para que ideas tangenciales caigan en `creative_chaos` (25–38 dmg, `is_critical=false`) y solo soluciones ingeniosas a la debilidad del rival o combos de 2 turnos disparen `is_critical=true` (>=85 dmg)."*
- **Si Stage 1 tarda más de 1.5 segundos**:
  > *"Revisa en `ai_bridge.py` que `thinkingConfig: {"thinkingBudget": 0}` esté activo en `generationConfig`, que `CLIENT.warmup()` pre-caliente `_HTTPSPool` al arrancar y que el prompt de usuario solo envíe `enc_compact` (sin `tauntLines` ni campos de UI)."*
- **Si un combo en 2 turnos no se activa con un sinónimo común**:
  > *"Agrega el sinónimo detectado en el playtest al bloque de detección de estados/combos tanto en `ai_bridge.py` (`SYSTEM_INSTRUCTION` + `fallback_battle_evaluate`) como en `battle_worker.lua` (`standaloneLuaEvaluate`), y añade un caso de regresión en ambos suites de test."*
