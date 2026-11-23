# FASE 04 — Ritual de Flechas Mágicas, Anticipación Viva y UX Minimalista Estilo Final Fantasy

| Campo | Detalle |
| :--- | :--- |
| **Fase** | `FASE 04` — Ritual de Flechas (Time-Buying Activo), Anticipación Viva del Rival, HUD Limpio Estilo Final Fantasy y Regla de Semi-Pista Tras 2 Fallos |
| **Duración estimada (Hackathon)** | **2.0 – 3.0 horas** (en paralelo con 3 subagentes de Codex + auditoría visual/UX de Astra) |
| **Prerrequisitos (Gate de entrada)** | - **Fase 03 completada**: `encounters.lua` (con `introLine` y `semiHintLine`), `ai_bridge.py` (devolviendo `anticipation_line`, `is_critical`, `outcome_type`, `adds_stage_state`, `combo_triggered`, `ritual_theme_color`), `battle_worker.lua` y `sprite_worker.lua` conectados a `main.lua`.<br>- Fuente tipográfica `assets/fonts/PTSans.ttc` cargada y retratos del Pudú (`happy`, `shocked`, `angry`) o placeholders listos. |
| **Entregables concretos** | 1. `spell_ritual.lua` (ritual de flechas `↑ ↓ ← →` / `WASD`, flechas dibujadas como **2 polígonos convexos**, puntero rebotando `"APRIETA"`, carga `+8%` sin castigo de ritmo, orbe acotado arriba del sombrero, 1 solo texto flotante a la vez, auto-extensión `+2 BONUS` y emisión de luces `collectLights()`).<br>2. `battle_hud.lua` (HUD minimalista estilo Final Fantasy de 78 px, barra de vida diegética del rival + etiquetas compactas de estados `MOJADO`/`ENJABONADO`/etc., cero chips de pistas, cero puntos de compás ni botón Bailar, iconos 100% vectoriales anti-tofu).<br>3. Integración en `main.lua` de la **Anticipación Viva del Rival** durante el ritual (`scared`/`laughing` + globo `anticipation_line` limpio arriba de la cabeza) y la **Regla Estricta de Semi-Pista tras 2 fallos seguidos** (`nonCritMissCount >= 2` -> `semiHintLine`).<br>4. Capturas CLI verificadas (ritual normal, ritual con anticipación, ritual `+2 BONUS`, HUD en turno del jugador con estados activos, y turno tras 2 fallos mostrando `semiHintLine`). |

---

## 1. Objetivo de Producción y Alcance (Qué SÍ y Qué NO hacer en esta fase)

El objetivo de la **Fase 04** es resolver dos problemas críticos de cualquier juego con IA generativa:
1. **Eliminar por completo la sensación de espera ("Cargando...")**: mientras Stage 1 juzga el prompt y Stage 2 genera el sprite HD-2D en vivo, el jugador realiza un **ritual mágico corto de flechas** que se siente divertido, táctil, sin estrés de ritmo, y convierte el tiempo de red en carga de potencia real (`+8%` por flecha) + suspenso cómico al ver al rival reaccionar en vivo.
2. **Mantener una pantalla ultra-limpia y legible de un vistazo**: estética clásica **Final Fantasy** con máximo aire para el arte HD-2D, los sprites generados y la comedia — sin sobrecarga de UI, sin spoilers de prompts y sin cuadros "tofu" (`□`) en la tipografía.

### Qué SÍ construir en esta fase

1. **Ritual de Flechas Mágicas — Time-Buying Activo (`spell_ritual.lua`)**:
   - **Inicio limpio**: arranca con **4 flechas** elegidas de un banco de patrones ágiles (nunca 3 iguales seguidas). Acepta tanto **Flechas (`↑ ↓ ← →`)** como **`WASD`** (`up/down/left/right/w/a/s/d`).
   - **Carga sin estrés (cero penalización de ritmo)**: el jugador presiona a su propio ritmo cómodo. Cada acierto suma **`+8%` de potencia** (`powerBonus` desde `1.00` hasta `1.64`), dispara un chime musical ascendente (`playArrowChime` / `chime_1..3`), 18 chispas/estrellas, anillo expansivo y rayo curvo Bézier que vuela desde la casilla hacia el orbe del Pudú. Un error solo hace vibrar suavemente la casilla (`shake = 1.0`) y permite reintentar al instante sin castigo.
   - **REGLA TÉCNICA CRÍTICA DE LÖVE2D — Flechas Convexas de 2 Partes (`drawArrowGlyph`)**:
     > **NUNCA** dibujes una flecha como un único polígono de 7 vértices con `love.graphics.polygon("fill", ...)`: LÖVE2D triangula con *triangle fan* y colapsa/deforma polígonos cóncavos (no-convexos).
     > Dibuja SIEMPRE cada flecha rotando el canvas (`0`, `π/2`, `π`, `-π/2`) y combinando **2 primitivas estrictamente convexas**:
     > 1. **Cuerpo rectangular** (`love.graphics.rectangle("fill", -s*0.94, -s*0.27, s*1.00, s*0.54, 2, 2)`).
     > 2. **Punta triangular** (`love.graphics.polygon("fill", -s*0.04, -s*0.86, s*1.04, 0.0, -s*0.04, s*0.86)`).
     > Precedidas por un pase de **contorno oscuro** ligeramente inflado (rectángulo + triángulo) y rematadas por un brillo blanco sutil en el eje superior.
   - **Legibilidad instantánea de la flecha activa**:
     - Color fijo por dirección (`up` = Cian, `down` = Magenta, `left` = Dorado, `right` = Lima) + letra `W/A/S/D` discreta en la esquina inferior derecha de la casilla activa.
     - Contraste fuerte de escala: casilla activa **`1.28x`** con halo respiratorio suave vs casillas futuras `0.80x` atenuadas y completadas `0.86x` en verde esmeralda.
     - **Puntero triangular amarillo rebotando + etiqueta `"APRIETA"`** con borde oscuro justo encima de la casilla activa.
     - **Geometría anti-solapamiento garantizada**: en 720p, el panel de flechas se fija con `panelY >= 126` (`barY = max(126 + panelH/2, floor(screenH * 0.235))`) y la píldora de estado de 1 línea va arriba (`statusY = max(56, panelY - statusH - 42)`), dejando holgura limpia para que la píldora, `"APRIETA"` y las flechas jamás se toquen.
   - **Orbe acotado + Disciplina de 1 solo texto flotante**:
     - Orbe mágico anclado arriba del sombrero del Pudú (`ox = puduX + 12`, `oy = puduY - 134 + sin*5`), radio acotado `<= 28 px` durante la carga (solo se expande en los `0.28s` de clímax `"¡¡INVOCANDO!!"`). Emite luces HDR vía `collectLights()`.
     - `_spawnWord()` elimina cualquier texto flotante `"word"` previo antes de crear el nuevo -> **máximo 1 palabra de carga en pantalla a la vez** (`¡BRILLANTE!`, `¡CHISPA!`, `¡GENIAL!`, `¡MAGIA!`, `¡PODER!`, `¡BONUS +8%!`), eliminando por completo el apilado de textos cuando el jugador presiona rápido.
   - **Extensión Automática `+2 BONUS` (Time-Buying Inteligente)**:
     - Al completar la última flecha: si `_canUnleashNow()` es verdadero (Stage 1 listo **Y** sprite listo o no requerido, o se alcanzó `SAFETY_TIMEOUT = 12.0s`), dispara `_triggerUnleash()` de inmediato.
     - Si el sprite en vivo aún se está generando en Stage 2 y `#sequence < MAX_SEQUENCE_LEN` (`10`), añade automáticamente **`+2` flechas doradas/arcoíris** con la etiqueta compacta **`¡BONUS! +2 flechas`** debajo del panel.
     - Si el jugador termina las 10 flechas y el sprite llega medio segundo después, `SpellRitual:update()` suelta el hechizo automáticamente al instante.

2. **Reacción de Anticipación Viva del Rival (`main.lua`)**:
   - Apenas `pollWorkers()` recibe Stage 1 mientras `Game.battlePhase == "ritual"`:
     - Si `res.is_critical`, `res.combo_triggered ~= "none"` o `res.outcome_type == "super_funny_ko"` -> cambia `Game.enemyReaction = "scared"` y muestra `res.anticipation_line` (fallback: `"¡Espera... eso se ve muy malo!"`).
     - Si `res.outcome_type == "backfire"` -> cambia `Game.enemyReaction = "laughing"` y muestra `res.anticipation_line` (fallback: `"¿En serio vas a invocar eso?"`).
     - En otros casos mantiene pose normal + `anticipation_line` si existe.
   - **Posicionamiento seguro del globo de anticipación**: dibujado en crema con cola triangular encima de la cabeza del rival (`ay = enemyY + tr.offsetY - 216`, `ax` restringido al cuadrante derecho `clamp(enemyX - aw/2, w * 0.58, w - aw - 16)`, `aw <= 280`), garantizando que **nunca tape la barra centrada de flechas ni la cara del rival**.

3. **HUD Minimalista Estilo Final Fantasy (`battle_hud.lua`)**:
   - Ventanas clásicas `drawFFWindow()` con degradado azul profundo, doble borde oscuro + blanco nítido y sombra suave.
   - **Barra superior mínima**: chip izquierdo (Bioma en Explore / Nombre del rival en Battle), controles derechos compactos (Toggle Música con icono vectorial de nota musical, `Mapa [Esc]` / `Álbum`, `Director [F2]`), y toast narrativo central que **se oculta automáticamente durante `ritual`**.
   - **Franja inferior de batalla ultra-limpia (`78 px` de alto)**:
     - Izquierda (`196 px`): retrato del Pudú (`happy`/`shocked`/`angry`) + etiqueta `PUDÚ` + barra de HP verde.
     - Derecha: caja de prompt pura (`"Escribe qué generar para vencer al rival..."` con cursor parpadeante `|`) + botón **`CONJURAR`** (se activa con >= 2 caracteres). Durante fases ocupadas muestra un mensaje limpio de 1 línea (`"Aprieta las FLECHAS (o WASD) para completar el hechizo"`, `"Turno del rival..."`, etc.).
   - **Barra diegética del rival + Etiquetas de Estado (`drawRivalStageBar`)**:
     - Debajo de los pies del rival (`ey + 24`): barra de HP compacta (`156 px`) + fila centrada de etiquetas (`ty = by + 20`) para `enemyStatusTag` (dorado) y los estados de escenario activos (`MOJADO`, `CONGELADO`, `ENJABONADO`, `ACEITOSO`, `CALIENTE`, `OSCURO`, `RUIDOSO`, `PEGAJOSO`) con colores distintivos — esto permite que el jugador descubra los super-combos en 2 turnos sin ningún texto de tutorial!
   - **Modal compacto de Victoria / Derrota**: muestra con qué prompt venció al rival, nombre del combo si aplicó, y botones `VOLVER AL MAPA` / `REVANCHA` (`REINTENTAR` en derrota).

4. **Regla Estricta de Semi-Pista Tras 2 Fallos (`main.lua`)**:
   - Al entrar a combate, el rival SOLO dice su `introLine`.
   - En `applySummonImpactEffects()`:
     - Si `isCrit == true`: resetea `Game.nonCritMissCount = 0` y `Game.pendingSemiHint = false`.
     - Si no fue crítico y `outcome_type ~= "heal_pudu"`: incrementa `Game.nonCritMissCount`. Al llegar a **`>= 2`**, marca `Game.pendingSemiHint = true` y reinicia `Game.nonCritMissCount = 0`.
   - Al terminar el contraataque enemigo y volver a `player_turn`, si `Game.pendingSemiHint == true`, el rival dice su `enc.semiHintLine` en el globo de diálogo (`5.2s`) y limpia la bandera.

5. **Regla Estricta Anti-Tofu (`PTSans.ttc`)**:
   - `PTSans.ttc` solo cubre ASCII + Latin-1 (`áéíóúüñ¡¿·`).
   - **PROHIBIDO** escribir emojis (`🔥✨💧`), flechas Unicode (`↑↓←→`), notas (`♪♫`) o estrellas (`★✦`) dentro de cualquier `love.graphics.print` / `printf` (se renderizan como cuadros rotos `□`).
   - Todo símbolo gráfico (flechas, nota musical, estrellas, puntero, icono de mute) se dibuja con geometría vectorial en `love.graphics`.

### Qué NO hacer en esta fase

- **NO** agregar chips de sugerencias/pistas de prompts en la barra inferior (arruina la magia de creatividad libre).
- **NO** agregar puntos de compás, medidor de ritmo estricto, ventana "PERFECT/MISS" ni botón "Bailar" en el HUD.
- **NO** mostrar un spinner genérico o pantalla congelada de `"Cargando..."` mientras la IA piensa.
- **NO** meter el Panel Director completo ni el Álbum de Locuras en esta fase si aún no existen (solo dejar el botón/callback limpio si ya existe el módulo; su construcción detallada pertenece a Fase 05/06).

---

## 2. Modo Assets: ¿Ya tengo sprites/música o los incorporo después?

| Modo | Situación del equipo | Cómo operar en Fase 04 |
| :--- | :--- | :--- |
| **Modo A — Assets ya listos** | Ya tienes `assets/fonts/PTSans.ttc`, retratos `assets/ui/portraits/pudu_{happy,shocked,angry}.png` y SFX `chime_1..3`, `orb_gain`, `sfx_spell_miss`, `sfx_spell_unleash`. | `battle_hud.lua` dibuja los retratos pixel-art nítidos con `nearest`, `spell_ritual.lua` dispara los chimes ascendentes reales y `main.lua` usa `PTSans.ttc` en 5 tamaños (`12`, `14`, `17`, `26`, `36`). |
| **Modo B — Sin assets todavía (Placeholder-first)** | Aún no tienen la fuente, retratos ni SFX finales. | 1. **Cero bloqueo visual**: tanto `spell_ritual.lua` como `battle_hud.lua` son **95% dibujo vectorial nativo de LÖVE2D** (`drawFFWindow`, `drawArrowGlyph`, `drawFourPointStar`, `drawMusicNoteIcon`, `drawBar`).<br>2. Si faltan retratos PNG, `battle_hud.lua` deja el marco azul oscuro limpio (o dibuja un busto geométrico temporal) sin crashear.<br>3. Si falta `PTSans.ttc`, `mkFont(sz)` cae a `love.graphics.newFont(sz)` manteniendo intacta la regla anti-tofu (ASCII + Latin-1 únicamente).<br>4. Si faltan los WAV de chimes, `audio:playArrowChime` puede emitir un tono sinusoidal corto o degradar en silencio sin errores. |

---

## 3. División Codex vs Astra + Subagentes de esta Fase

| Rol | Herramienta | Propiedad exclusiva de archivos | Responsabilidad principal |
| :--- | :--- | :--- | :--- |
| **Orquestador Principal** | **Codex (Lead)** | `main.lua` (conexión ritual, anticipación viva, contador `nonCritMissCount >= 2`, enrutado de teclado/ratón, CLI `--test-ritual`) | Integra `SpellRitual` y `BattleHUD`, coordina el orden de dibujo (FX -> Speech/Anticipation -> Ritual -> HUD) para cero solapamientos y captura screenshots CLI. |
| **Subagente A — Ritual de Flechas** | **Codex Subagent** | `spell_ritual.lua` | Implementa el minijuego de time-buying: 4 flechas iniciales + extensión `+2 BONUS` (máx. 10), `drawArrowGlyph` convexo de 2 partes, puntero `"APRIETA"`, orbe acotado, 1 solo texto flotante, partículas/rayos Bézier y `collectLights()`. |
| **Subagente B — HUD Minimalista FF** | **Codex Subagent** | `battle_hud.lua` | Implementa ventanas Final Fantasy, barra superior mínima, franja inferior de 78 px sin spoilers ni ritmo, `drawRivalStageBar` con pills de los 8 estados de escenario, modal Victoria/Derrota y 100% cumplimiento anti-tofu. |
| **Subagente C — Verificación & Auditoría Anti-Tofu / Layout** | **Codex Subagent** | `tests/test_phase04_ui.lua` (y script de escaneo anti-tofu) | Escanea todos los `.lua` de UI buscando caracteres fuera de Latin-1/ASCII, prueba la máquina de estados del ritual (incluyendo `+2 BONUS` y timeout 12s) y valida `nonCritMissCount >= 2` -> `semiHintLine`. |
| **UX & Visual Reviewer** | **Astra** | *(Solo lectura + inspección de capturas PNG)* | Revisa capturas reales en 1280x720: audita legibilidad instantánea de las flechas, contraste del puntero `"APRIETA"`, cero solapamiento del globo `anticipation_line`, limpieza Final Fantasy del HUD y ritmo emocional de la semi-pista. |

---

## 4. Prompt Maestro para Codex (Copiar y Pegar — Orquestación con Subagentes)

```text
Actúa como Tech Lead de Pudú Fantasy ejecutando la FASE 04 (Ritual de Flechas Mágicas, Anticipación Viva del Rival y UX Minimalista Estilo Final Fantasy).

REGLAS TÉCNICAS INNEGOCIABLES:
1. FLECHAS CONVEXAS DE 2 PARTES: en LÖVE2D los polígonos no-convexos colapsan al dibujarse con `love.graphics.polygon("fill", ...)`. TODA flecha en `spell_ritual.lua` DEBE dibujarse con rotación + 2 primitivas convexas separadas: un cuerpo rectangular (`rectangle`) y una punta triangular (`polygon` de 3 vértices), con pase de contorno oscuro y brillo interior.
2. CERO ESTRÉS DE RITMO: cada flecha correcta suma `+8%` de poder (1.0 -> 1.64 max) al ritmo propio del jugador; equivocarse solo vibra suavemente la casilla para reintentar al instante.
3. CERO SOLAPAMIENTOS Y 1 SOLO TEXTO FLOTANTE:
   - En 720p, el panel de flechas mantiene `panelY >= 126`, la píldora de estado va en `statusY = max(56, panelY - statusH - 42)`, el puntero rebotando `"APRIETA"` va justo arriba de la casilla activa, y el badge `"¡BONUS! +2 flechas"` debajo del panel.
   - `_spawnWord()` borra cualquier palabra flotante previa antes de crear una nueva (máximo 1 texto de carga a la vez sobre el orbe).
   - El orbe arriba del sombrero del Pudú mantiene radio acotado (`<= 28 px` antes del clímax de `0.28s`).
4. CERO TOFU EN `PTSans.ttc`: prohibido usar emojis, flechas Unicode (`↑↓←→`), notas (`♪`) o estrellas (`★`) en strings dibujados con `print`/`printf`. Solo ASCII + Latin-1 (`áéíóúüñ¡¿·`) e iconos vectoriales en `love.graphics`.
5. HUD ULTRA-LIMPIO Y REGLA DE PISTAS:
   - Cero chips de pistas/sugerencias de prompts, cero puntos de compás y cero botón "Bailar".
   - El rival solo dice `introLine` al iniciar, y ÚNICAMENTE si el jugador falla 2 veces seguidas en sacar crítico (`nonCritMissCount >= 2`, ignorando `heal_pudu`) repite su `semiHintLine` sutil al volver a `player_turn`.

ORQUESTACIÓN EN PARALELO (lanza 3 subagentes):
- Subagente A (`spell_ritual.lua`): implementa clase `SpellRitual` completa (`new`, `start`, `cancel`, `setAiReady`, `setSpriteReady`, `getMultiplier`, `getLastDirection`, `isComplete`, `onKeyPressed`, `update`, `draw`, `collectLights`) con 4 flechas iniciales, `WASD`/flechas, colores por dirección (`up` cyan, `down` magenta, `left` gold, `right` lime), puntero `"APRIETA"`, `drawArrowGlyph` convexo de 2 partes, auto-extensión `+2 BONUS` (hasta 10 flechas) si Stage 1 o Stage 2 aún no terminan, `SAFETY_TIMEOUT = 12.0s`, rayos Bézier hacia el orbe y círculo arcano bajo el Pudú.
- Subagente B (`battle_hud.lua`): implementa clase `BattleHUD` estilo Final Fantasy (`drawTopBar`, `drawRivalStageBar`, `drawExploreBar`, `drawBattleStrip` de 78px, `drawVictoryOrDefeat`, `openPrompt`, `closePrompt`, `addText`, `backspace` UTF-8 seguro, `hitTest`), icono vectorial `drawMusicNoteIcon`, y etiquetas compactas de `stageStates` (`MOJADO`, `CONGELADO`, `ENJABONADO`, `ACEITOSO`, `CALIENTE`, `OSCURO`, `RUIDOSO`, `PEGAJOSO`) debajo de la barra de HP del rival.
- Subagente C (`tests/test_phase04_ui.lua`): crea tests unitarios sin GPU (mocks de `love`) que verifiquen:
  1) Escaneo anti-tofu de todos los literales de texto en `spell_ritual.lua`, `battle_hud.lua` y `main.lua` (falla si detecta algún codepoint fuera de ASCII/Latin-1 excepto `…` si se reemplaza por `..`).
  2) Lógica de `SpellRitual`: 4 flechas iniciales, `+8%` por acierto, error no bloquea ni resetea progreso, auto-extensión `+2` hasta máx. 10 cuando sprite no está listo, auto-disparo inmediato al llegar `setSpriteReady()`, máximo 1 `"word"` en `self.sparkles` tras 4 aciertos rápidos.
  3) Regla `nonCritMissCount`: 1 fallo no dispara pista, 2 fallos seguidos disparan `pendingSemiHint`, 1 crítico resetea el contador a 0, `heal_pudu` no cuenta como fallo.

INTEGRACIÓN EN `main.lua` (Lead):
- Conecta `SpellRitual` y `BattleHUD`.
- En `pollWorkers()`: al llegar `prompt_result` aprobado durante `battlePhase == "ritual"`, activa anticipación viva del rival (`scared` en crítico/combo, `laughing` en backfire) y guarda `Game.anticipationLine`.
- En `love.draw()`: dibuja el globo de `Game.anticipationLine` encima de la cabeza del rival (`ay = enemyY + tr.offsetY - 216`, `ax` clamped a `[w * 0.58, w - aw - 16]`) durante `ritual` sin tocar la barra de flechas ni el rostro del rival. Oculta el toast superior durante `ritual`.
- En `applySummonImpactEffects()` y salida de `enemy_counter`: implementa la regla exacta `nonCritMissCount >= 2` -> `enc.semiHintLine` por `5.2s`.
- En `love.keypressed()`: rutea `Enter`/`/` para abrir prompt, `WASD`/flechas hacia `spellRitual` durante `ritual`, y `Esc` para cancelar/volver al mapa.

VERIFICACIÓN OBLIGATORIA Y CAPTURAS CLI:
1. Ejecuta `luajit tests/test_phase04_ui.lua` y confirma 100% pass (incluyendo escaneo anti-tofu).
2. Genera 4 capturas CLI en 1280x720 y verifica visualmente cero solapamientos y cero tofu:
   - `screenshots/fase04_hud_clean.png`: `--mode=battle --encounter=1 --screenshot=screenshots/fase04_hud_clean.png --quit-after=2.0`
   - `screenshots/fase04_ritual_arrows.png`: `--mode=battle --encounter=1 --test-ritual --screenshot=screenshots/fase04_ritual_arrows.png --quit-after=2.0`
   - `screenshots/fase04_anticipation.png`: `--mode=battle --encounter=1 --mock --auto-prompt="nube de lluvia" --screenshot=screenshots/fase04_anticipation.png --quit-after=1.4`
   - `screenshots/fase04_stage_states.png`: `--mode=battle --encounter=1 --demo-combo=combo_electro --screenshot=screenshots/fase04_stage_states.png --quit-after=2.2`
3. Reporta logs, resultados de tests y las rutas exactas de las 4 capturas.
```

---

## 5. Prompts Individuales por Subagente

### Subagente A — Ritual de Flechas Mágicas (`spell_ritual.lua`)

```text
Crea únicamente `spell_ritual.lua` (sin editar `main.lua` ni `battle_hud.lua`).

ESPECIFICACIÓN EXACTA:
1. Estado e API pública:
   - `SpellRitual.new()`, `:start(promptText, themeColorHex)`, `:cancel()`, `:setAiReady(decisionResult, needsLiveSprite)`, `:setSpriteReady()`, `:getMultiplier()`, `:getLastDirection()`, `:isComplete()`, `:onKeyPressed(key, audio, beatSync)`, `:update(dt, beatSync, puduScreenX, puduScreenY)`, `:draw(screenW, screenH, puduScreenX, puduScreenY, fonts, beatSync)`, `:collectLights(out)`.
2. Mecánica de juego y time-buying:
   - Inicia con 4 flechas de un banco de patrones variados (nunca 3 iguales seguidas).
   - Acepta `up/down/left/right` y `w/a/s/d`.
   - Acierto: `+8%` multiplicador (`1.0` a `1.64`), `orbEnergy` sube, chime ascendente, 18 partículas estrella/prisma, anillo expansivo, rayo Bézier hacia el orbe y 1 palabra flotante (`PRAISE_WORDS` o `"¡BONUS +8%!"`).
   - Disciplina de texto único: `_spawnWord()` remueve cualquier entry con `kind == "word"` antes de insertar el nuevo.
   - Error: solo `item.shake = 1.0`, `sfx_spell_miss` y 6 chispas rojas; cero penalización ni bloqueo.
   - Time-buying: cuando `cursor > #sequence`, si AI + sprite están listos (o `elapsed >= 12.0`), entra en clímax (`CLIMAX_DURATION = 0.28s`, `"¡¡INVOCANDO!!"`). Si falta AI o sprite y `#sequence < 10`, añade `+2` flechas bonus arcoíris y muestra `"¡BONUS! +2 flechas"` debajo del panel durante `3.2s`. En `update()`, si el jugador ya terminó y acaba de llegar el sprite/AI, dispara `_triggerUnleash()` al instante.
3. Geometría y visual:
   - **CRÍTICO**: `drawArrowGlyph()` rota según dirección y dibuja **2 polígonos convexos separados** (rectángulo + triángulo) con pase de borde oscuro + relleno de color por dirección (`up` cian, `down` magenta, `left` oro, `right` lima) + brillo blanco superior.
   - Casilla activa a escala `1.28x` con halo respiratorio, puntero triangular amarillo rebotando + texto `"APRIETA"` arriba de la casilla, y letra `W/A/S/D` pequeña en la esquina inferior derecha.
   - Layout seguro en 720p: `panelY >= 126`, píldora de estado de 1 línea en `statusY = max(56, panelY - statusH - 42)`.
   - Orbe sobre el sombrero del Pudú (`ox = puduX + 12`, `oy = puduY - 134 + sin*5`) con radio acotado `<= 28 px` durante la carga, y círculo arcano giratorio bajo las pezuñas.
   - Cero caracteres fuera de ASCII/Latin-1 (regla anti-tofu).
```

### Subagente B — HUD Minimalista Estilo Final Fantasy (`battle_hud.lua`)

```text
Crea únicamente `battle_hud.lua` (sin editar `main.lua` ni `spell_ritual.lua`).

ESPECIFICACIÓN EXACTA:
1. Estética Final Fantasy clásica:
   - `drawFFWindow(x, y, w, h, accentTop, accentBot, alpha)`: sombra suave, degradado vertical azul en 5 franjas, borde exterior oscuro (3.5px) y borde interior blanco nítido (2px).
   - `drawBar(x, y, w, h, ratio, fillCol)`: barra con fondo oscuro, relleno brillante, reflejo superior y borde fino.
   - `drawMusicNoteIcon(cx, cy, muted)`: corchea doble dibujada 100% con primitivas `ellipse`/`line` (más diagonal roja si `muted`) — CERO símbolos Unicode.
2. Composición ultra-limpia:
   - `drawTopBar(state, screenW)`: izquierda = 1 solo chip contextual (Bioma + `(defeated/9)` en Explore, o nombre del rival en Battle); derecha = `Director [F2]`, `Álbum X/9 [J]` (Explore) o `Mapa [Esc]` (Battle en `player_turn`), y botón de música vectorial. Toast central auto-ajustado que NO se dibuja si `state.battlePhase == "ritual"`.
   - `drawRivalStageBar(state, ex, ey)`: debajo del rival (`by = ey + 24`, ancho `156`), barra de HP + píldoras compactas lado a lado (`ty = by + 20`) para `enemyStatusTag` y `state.stageStates` con paleta fija por estado (`mojado`, `congelado`, `enjabonado`, `aceitoso`, `caliente`, `oscuro`, `ruidoso`, `pegajoso`).
   - `drawBattleStrip(state, screenW, screenH)`: franja inferior delgada de **78 px** de alto (`totalW <= 860`). Tarjeta izquierda (`196 px`): retrato Pudú + `PUDÚ` + barra HP. Tarjeta derecha: caja de texto pura + botón `CONJURAR` (`124 px`). **PROHIBIDO** agregar chips de sugerencias de prompts, puntos de compás o botón "Bailar".
   - `drawVictoryOrDefeat(state, screenW, screenH)`: modal compacto arriba-centro mostrando el prompt vencedor, badge de combo si hubo, y botones `VOLVER AL MAPA`/`REVANCHA` o `REINTENTAR`.
3. Entrada UTF-8 segura: `addText(t)` (límite 68 bytes/chars), `backspace()` que borra codepoints UTF-8 completos (tildes/`ñ` no dejan bytes huérfanos), y `hitTest(mx, my)`.
4. Cumplimiento estricto anti-tofu: únicamente ASCII + Latin-1 (`áéíóúüñ¡¿·`).
```

### Subagente C — Suite de Tests de Ritual, Semi-Pista y Anti-Tofu (`tests/test_phase04_ui.lua`)

```text
Crea y ejecuta `tests/test_phase04_ui.lua` para validar toda la Fase 04 sin requerir ventana gráfica.

COBERTURA OBLIGATORIA:
1. **Escaneo estricto Anti-Tofu**: lee `spell_ritual.lua`, `battle_hud.lua`, `encounters.lua` y `main.lua`, y verifica que ningún string visible de UI contenga bytes UTF-8 fuera de ASCII + Latin-1 (`U+0020..U+00FF` más guiones/elipsis permitidas si aplica; rechaza emojis, flechas Unicode `U+2190..U+21FF`, símbolos musicales `U+2669..U+266F` y estrellas `U+2605..U+273F`).
2. **Pruebas unitarias de `SpellRitual`**:
   - `start()` genera 4 flechas sin 3 repeticiones consecutivas.
   - Cada `onKeyPressed` correcto incrementa `powerBonus` en `+0.08` (tope `1.64`), y tras 4 pulsaciones rápidas `sparkles` contiene a lo sumo 1 elemento con `kind == "word"`.
   - Tecla incorrecta incrementa `misses` pero NO avanza ni bloquea `cursor`.
   - Si `aiDecisionReady == false` o `needsLiveSprite == true and not spriteReady` al terminar la flecha 4, se agregan exactamente `+2` flechas `bonus = true` (hasta máximo 10) y se activa `overchargeBannerTimer > 0`.
   - Cuando llega `setSpriteReady()` después de terminar la secuencia, `update()` dispara `readyToUnleash = true` y tras `0.3s` `isComplete() == true`.
   - Verifica en `draw()` (con stub de `love.graphics`) que `love.graphics.polygon` nunca recibe más de 8 floats (4 vértices) para la punta de flecha ni falla por no-convexidad, y que `panelY >= 126` y `statusY >= 56` con separación positiva en 1280x720.
3. **Pruebas de Regla de 2 Fallos**: simula la lógica de `nonCritMissCount` (fallo 1 -> sin pista; `heal_pudu` -> no suma fallo; fallo 2 -> `pendingSemiHint = true` y contador vuelve a 0; crítico -> resetea contador a 0).
```

---

## 6. Prompt para Astra (Design Review de Humor, Prompts y UX Limpia)

Pásale a **Astra** las 4 capturas CLI (`screenshots/fase04_*.png`) junto con este prompt:

```text
Actúa como UX Director & Game Feel Reviewer (Astra) auditando la FASE 04 de Pudú Fantasy.

Inspecciona las capturas adjuntas (`fase04_hud_clean.png`, `fase04_ritual_arrows.png`, `fase04_anticipation.png`, `fase04_stage_states.png`) y lee en solo-lectura `spell_ritual.lua`, `battle_hud.lua` y las secciones de `anticipationLine` / `nonCritMissCount` en `main.lua`.

AUDITA ESTOS 7 PUNTOS CON CRITERIO ESTRICTO DE HACKATHON (VEREDICTO + FIXES EXACTOS):
1. **Legibilidad instantánea de las flechas (Test de 0.5 segundos)**:
   - Al mirar `fase04_ritual_arrows.png` medio segundo, ¿es 100% obvio qué tecla apretar AHORA?
   - ¿Las 4 direcciones se ven nítidas, gruesas, convexas y sin deformaciones de triángulos? ¿Se distinguen bien por color + silueta + puntero `"APRIETA"`?
2. **Cero sobrecarga visual y cero solapamientos**:
   - Verifica holguras reales entre: (a) barra superior, (b) píldora de estado del ritual, (c) etiqueta `"APRIETA"`, (d) casillas de flechas, (e) orbe + texto flotante único sobre el sombrero del Pudú, y (f) globo `anticipation_line` sobre el rival.
   - Señala cualquier píxel de solapamiento o ruido innecesario.
3. **Anticipación viva del rival**:
   - En `fase04_anticipation.png`, ¿la pose nerviosa/burlona del rival + su globo `anticipation_line` se sienten vivos y graciosos sin taparle la cara ni distraer de las flechas?
4. **Pureza del HUD Minimalista Final Fantasy**:
   - ¿Queda algún resto de chips de pistas de prompts, puntos de compás, botón "Bailar" o texto relleno?
   - ¿La franja inferior de 78 px deja respirar el escenario HD-2D y a los personajes?
5. **Descubrimiento de estados de escenario**:
   - En `fase04_stage_states.png`, ¿las píldoras (`MOJADO`, `ENJABONADO`, etc.) bajo la barra de vida del rival se leen nítidas y te invitan a combinar un segundo elemento sin arruinar el minimalismo?
6. **Anti-Tofu Check**:
   - ¿Hay algún cuadrado roto `□`, acento mal recortado o símbolo faltante en alguna captura?
7. **Ritmo de la regla de 2 fallos (`semiHintLine`)**:
   - ¿Se siente justo esperar exactamente 2 intentos no críticos antes de que el rival suelte la semi-pista? ¿Permite experimentar libremente sin frustrar a un jurado de hackathon que prueba el juego 2 minutos?

Devuelve máximo 6 ajustes priorizados (P0 bloqueantes visuales primero, P1 polish después) listos para aplicar en 10 minutos.
```

---

## 7. Gate de Iteración en Equipo (Playtest de 5 min + Definition of Done)

### Playtest relámpago de 5 minutos (5 prompts locos en vivo con el equipo)

Pongan a alguien del equipo que **NO** escribió el código de esta fase frente al teclado (sin darle explicaciones verbales!) para probar la intuición real de la UX con estos **5 prompts en vivo**:

1. **Test Cero Instrucciones + Fluidez del Ritual**: contra *Niño del Helado Triple*, escribe **`nube de lluvia`** y presiona `Enter`.
   - *Qué observar*: ¿Entendió en `<1 segundo` que debía apretar las flechas/`WASD` gracias al puntero `"APRIETA"`? ¿Sintió satisfacción con los rayos hacia el orbe sin estresarse por timing?
2. **Test Anticipación Viva + Time-Buying `+2 BONUS`**: escribe un prompt creativo nuevo (sin caché) como **`pinguino ninja con heladera`** o **`ornitorrinco dj`**.
   - *Qué observar*: apenas llega Stage 1 (~0.8s), el rival cambia de cara (`scared` o normal) y suelta su `anticipation_line` arriba de la cabeza; si el sprite live tarda ~3s, aparecen las `+2 BONUS` flechas arcoíris y el jugador **nunca** ve una pantalla congelada.
3. **Test Anticipación Burlona en Backfire**: contra *Niño del Helado Triple*, escribe **`paraguas`** (o **`cojín gigante`** contra *Gato Guatón*).
   - *Qué observar*: mientras aún presiona las flechas, el rival se pone en pose `laughing` y dice algo burlón como *"¿En serio vas a invocar ESO? ¡Ja!"* — anticipando el autogol cómico.
4. **Test Regla Estricta de 2 Fallos -> `semiHintLine`**: contra *Mimo del Muro*, escribe 2 objetos random no críticos seguidos (ej. **`silla`** y luego **`lápiz`**).
   - *Qué observar*: tras el 1er intento NO aparece pista; recién al volver al turno después del 2do fallo seguido, el Mimo suelta su `semiHintLine` sutil en el globo (sin chips de pistas ni spoilers en el HUD).
5. **Test Descubrimiento de Combo vía Etiqueta de Estado**: contra *Turista Selfie*, escribe **`balde de agua`** (observa que aparece la etiqueta azul `MOJADO` debajo de su barra de HP) y en el siguiente turno escribe **`rayo`**.
   - *Qué observar*: la etiqueta `MOJADO` es inmediatamente visible, invita al combo, y en el 2do turno se dispara `¡COMBO ELECTRO-CHARCO!` con anticipación de pánico.

### Definition of Done (Checklist de salida de Fase 04)

- [ ] Las 4 flechas direccionales se dibujan con 2 polígonos convexos (rectángulo + triángulo) sin artefactos visuales en LÖVE2D.
- [ ] Acepta tanto `↑ ↓ ← →` como `WASD`, suma `+8%` por acierto sin penalización de ritmo, y muestra a lo sumo 1 texto flotante de carga sobre el orbe acotado (`<= 28 px`).
- [ ] La auto-extensión `+2 BONUS` se activa suavemente cuando un sprite en vivo tarda más que las 4 flechas iniciales, y el hechizo se suelta automáticamente al terminar sin pantallas congeladas.
- [ ] Al llegar Stage 1 durante el ritual, el rival reacciona en vivo (`scared`/`laughing`) y muestra su `anticipation_line` sin tapar su rostro ni la barra de flechas.
- [ ] `battle_hud.lua` mantiene franja inferior de 78 px estilo Final Fantasy: cero chips de pistas, cero puntos de compás, cero botón "Bailar".
- [ ] La regla `nonCritMissCount >= 2` dispara `semiHintLine` exactamente tras 2 intentos no críticos (excluyendo curas) y se resetea con un crítico.
- [ ] Las etiquetas compactas de estados (`MOJADO`, `ENJABONADO`, etc.) se muestran limpiamente debajo de la barra de vida del rival.
- [ ] Escaneo anti-tofu 100% limpio (cero caracteres rotos `□` en `PTSans.ttc`; nota musical y flechas 100% vectoriales) y las 4 capturas CLI aprobadas por Astra.

### Prompts rápidos de iteración (si algo falla en el playtest)

- **Si las flechas se solapan con `"APRIETA"` o la píldora superior en resoluciones pequeñas**:
  > *"Ajusta `_getTileLayout()` y `statusY` en `spell_ritual.lua` para garantizar al menos `42 px` libres entre `statusY + statusH` y `panelY`, y escala `tileSize` proporcionalmente si `screenW < 1024`. Regenera `fase04_ritual_arrows.png`."*
- **Si el globo de `anticipation_line` toca las flechas cuando el texto es largo**:
  > *"En `main.lua`, limita `aw` del globo de anticipación a `260 px`, usa `fonts.small:getWrap()` para calcular altura dinámica de 1–2 líneas, y ancla `ax = clamp(enemyX - aw*0.5, w * 0.62, w - aw - 16)` para mantenerlo siempre en el tercio derecho lejos de la barra de flechas."*
- **Si un jugador presiona muy lento o muy rápido las flechas**:
  > *"Asegura en `spell_ritual.lua` que no exista ningún timer que penalice presionar lento (salvo `SAFETY_TIMEOUT = 12s` solo cuando el jugador ya completó la secuencia), y que pulsar rápido nunca apile palabras flotantes verificando `_spawnWord()`."*
- **Si aparece algún cuadro roto (`□`) en texto de IA o UI**:
  > *"Agrega una función de sanitización Latin-1 en `battle_hud.lua` y `ai_bridge.py` (`_clip`) que remueva emojis y reemplace flechas/símbolos fuera de Latin-1 por equivalentes limpios antes de renderizar con `PTSans.ttc`, y vuelve a correr `tests/test_phase04_ui.lua`."*
