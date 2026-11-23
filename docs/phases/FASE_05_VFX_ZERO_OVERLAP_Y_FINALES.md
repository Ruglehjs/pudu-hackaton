# FASE 05 — VFX Zero-Overlap, 6 Super-Combos, Finales Cómicos y Álbum de Locuras (`[J]`)

| Campo | Detalle |
| :--- | :--- |
| **Fase** | **05 de 07** — Jugo Visual, Espectáculo de Combos, Finales Cómicos y Colección Persistente |
| **Duración estimada en hackathon** | **2.5 – 3.5 horas** (ejecución paralela con 3 subagentes de Codex + 1 pase de auditoría visual con Astra) |
| **Prerrequisitos (Gate de entrada)** | Fase 04 superada: bucle completo de batalla por turnos operativo (`battle_enter → player_turn → ritual → impact_hold → enemy_counter / victory`), contratos JSON del árbitro IA devolviendo `delivery_style`, `particle_fx`, `enemy_reaction`, `combo_triggered`, `combo_name`, `is_critical`, `keep_prop_on_stage`, `prop_anchor`, y `main.lua` con anclas de escenario `StageRenderer.getBattleAnchors(w, h)` + soporte de luces dinámicas `collectLights`. |
| **Entregables concretos** | 1. `battle_fx.lua` completo con **Arquitectura de Carriles Zero-Overlap**, 16+ sistemas de partículas, invocaciones con 6 estilos de entrega, máx. 3 props persistentes, **6 Super-Combos visuales**, **5 Finales Cómicos de Derrota** y emisor de luces HDR `collectLights`.<br>2. `victory_album.lua` completo: modal 3×3 estilo RPG azul real biselado (**Álbum de Locuras**, `[J]`), persistencia dual en `victory_album.json` y revancha directa con 1 clic.<br>3. Integración limpia en `main.lua` y `battle_hud.lua` (ocultado de globos durante ritual/victoria/derrota, registro automático de victorias, botón HUD `[J]` y aplicación de `getDefeatTransform()` al sprite del rival). |

---

## 1. Objetivo de Producción y Alcance (Qué SÍ y Qué NO hacer en esta fase)

El propósito de esta fase es convertir un combate que "funciona" en un **espectáculo cómico instantáneamente legible en video, capturas y demo frente al jurado**, donde cada turno se sienta explosivo, gracioso y 100% libre de texto encimado.

### Qué SÍ hacer en esta fase
- **Construir `battle_fx.lua` con separación matemática estricta de carriles (Zero-Overlap Lanes)**:
  - **Carril 1 — Cielo Alto (`y = 108`, centrado `x = sw * 0.5`)**: Banner animado de Super-Combo (`activeCombo`) con cinta diagonal, bordes brillantes, estrellas de 4 puntas y outline de `4 px` (`#100818`).
  - **Carril 2 — Globos de Diálogo (`drawSpeechBubbles`)**:
    - Rival: arriba-izquierda del rival (`enemyX - 55`, `enemyY - 210`), acotado en `y ∈ [58, 148]` para nunca invadir la barra superior del HUD ni el rostro del rival.
    - **Esquive dinámico de Combo**: si `activeCombo` está visible y el globo del rival choca con el banner central (`bx < sw * 0.5 + 225` y `by < 144`), se desplaza automáticamente a la derecha (`bannerRight`) o desciende a `y = 150`.
    - Pudú: arriba del Pudú (`puduX + 10`, `puduY - 148`).
    - 5 estilos expresivos: `normal`, `shout` (puntiagudo amarillo/rojo tembloroso), `cry` (celeste con gotas cayendo), `laugh` (cálido saltando), `think` (burbujas).
    - **Regla de silencio visual**: en `main.lua`, los globos **NO se dibujan** durante `battlePhase == "ritual"` (donde viven las flechas y la píldora de anticipación), ni en `"victory"` / `"defeat"`.
  - **Carril 3 — Props Climáticos Aéreos (`overhead_weather` / `prop_anchor == "above_enemy"`)**:
    - Flotan alto sobre el rival (`py = math.max(96, eyTarget - 178)`) con offsets horizontales `{ 0, -24, 24 }` para que la lluvia o la nieve caigan por aire limpio sin tapar la cara del rival.
    - Límite duro de `MAX_PERSISTENT_PROPS = 3` (cola FIFO) y `MAX_PARTICLES = 420`.
  - **Carril 4 — Daño y `¡CRÍTICO!` con Staggering Anti-Solapamiento (`spawnFloatingText`)**:
    - Anclados arriba-derecha del rival (`exTarget + 86`, `eyTarget - 118`, más `critRightPad = 52` si es crítico) — dejando el lado izquierdo libre para la vena de furia o gota de sudor (`ex - 42`, `ey - 102`).
    - **Algoritmo anti-solapamiento de 6 pasadas**: si dos textos están a menos de `170 px` en X y `42 px` en Y, el nuevo sube `44 px` (mientras `y >= 74`); si ya toca el borde superior, escalona `±176 px` en X dentro de `[130, sw - 135]`.
    - Render con anillo precomputado de contorno grueso `4 px` `#100818` (`OUTLINE_RING_4PX`) + sombra + aura dorada aditiva en críticos.
  - **Carril 5 — Overlays de Reacción y Props de Suelo**:
    - Props en suelo (`melted_icecream`, cáscara de plátano, charco): `py = eyTarget + 16..18` (p. ej. helado derretido en `targetX - 58, targetY + 12`).
    - Charcos y resplandores traseros en `drawBackLayer()` (detrás del rival); overlays de reacción, combos y finales en `drawReactionOverlay()`; partículas frontales, números flotantes y banner de combo en `drawFrontParticles()` (nítidos, **después** del post-proceso/bloom).
- **Implementar los 6 Super-Combos visuales (`triggerComboSpectacle`)**:
  1. `combo_electro` (`¡COMBO ELECTRO-CHARCO!`): rayo principal + 2 ramificaciones desde el cielo (`topY = -12`) con brillo aditivo cian, núcleo amarillo y filamento blanco + silueta eléctrica estroboscópica en zigzag + anillo eléctrico en el piso + `flash`/`sparkles`.
  2. `combo_deep_freeze` (`¡COMBO HIELO TOTAL!`): prisma/cubo de hielo facetado translúcido (`drawFacetedIceCube`) que envuelve al rival con rebote `easeOutBack`, vetas especulares diagonales blancas, 4 destellos en esquinas y 6 copos cristalinos orbitando + `snow`/`sparkles`.
  3. `combo_steam_sauna` (`¡COMBO SAUNA EXTREMO!`): 9 nubes densas ascendentes de vapor blanco/rosa cálido + 4 anillos ascendentes de calor + `steam`/`bubbles`.
  4. `combo_slip_slide` (`¡COMBO RESBALÓN TURBO!`): 6 cintas espirales estilo tornado rodeando al rival + 5 estrellas doradas de mareo arriba + `wind`/`stars`/`bubbles`.
  5. `combo_fire_boom` (`¡COMBO SUPER-EXPLOSIÓN!`): explosión cómica starburst de 14 puntas (naranja exterior + núcleo dorado) + onda expansiva aditiva + 4 anillos ascendentes de humo de hollín + `explosion`/`fire`/`stars`.
  6. `combo_chaos` (`¡COMBO CAOS TOTAL!`): 12 rayos arcoíris aditivos rotativos + 2 anillos geométricos octogonales contrarrotativos + lluvia masiva de `confetti`/`stars`/`sparkles`.
- **Implementar los 5 Finales Cómicos de Derrota (`startDefeatFinale` + `getDefeatTransform`)**:
  1. `crying` / `sad`: rival desplomado temblando (`scaleY → 0.88`, `dy → +6`), **charco creciente de lágrimas** con ondas en `drawBackLayer()` (`rx: 22 → 76`), fuentes gemelas de lágrimas (`tears`) y **banderita blanca** ondeando (`drawSurrenderFlag`).
  2. `scared` / `chased` / `panicked`: sobresalto de `0.14 s` y **huida cohete fuera de pantalla hacia la derecha** (`dx: 0 → 460`, saltitos + fade-out) dejando una **nube de polvo giratoria estilo Looney Tunes** (`drawSpinningDustCloud`) y líneas de velocidad; ocultar overlays base cuando `dtf.alpha < 0.15` o `dtf.dx > 180`.
  3. `frozen`: escalofrío inicial (`0.22 s`) y encierro rígido dentro de un **bloque de hielo cristalino persistente y brillante** (`drawFacetedIceCube`) con escarcha animada.
  4. `happy_pacified` / `pacified`: rebote feliz (`dy = -abs(sin)*10`) rodeado de **4 corazones orbitando** y destellos dorados (`hearts` + `sparkles`).
  5. **K.O. clásico (`dizzy` / `splatted` / `defeated` / default)**: caída cómica ladeada (`rot → 0.24 rad`), **4 estrellas doradas orbitando sobre la cabeza** (`ey - 168`) y **banderita blanca de rendición** ondeando.
- **Construir `victory_album.lua` (Álbum de Locuras `[J]`)**:
  - Modal centrado 3×3 estilo ventana *Final Fantasy* azul real biselada (`drawFFWindow`), encabezado con progreso `(X / 9 Rivales Vencidos)`, botones `Limpiar` y `[X]`.
  - Tarjetas bloqueadas: silueta oscura + `?` + badge de bioma (`Bosque`, `Desierto`, `Costa`, `Ciudad`) + `#1..#9`.
  - Tarjetas desbloqueadas: retrato a color (`nearest`), badges (`Bioma`, `COMBO`, `CRÍTICO`, `xN`), cita dorada del prompt ganador (`Con: '<prompt>'`, wrap limpio a 2 líneas con truncado UTF-8 seguro para español), resumen cómico y clic directo para ir a revancha inmediata.
  - Persistencia dual automática en `victory_album.json` (directorio del proyecto / `.exe` fused + directorio de guardado de LÖVE).

### Qué NO hacer en esta fase
- **NO** diseñar ni exportar sprites PNG ni pistas de música definitivas aquí (eso pertenece a la **Fase 06**; los VFX y el Álbum funcionan desde el minuto 1 con fallbacks procedurales o placeholders existentes).
- **NO** dibujar el Panel Director `[F2]` ni el Hot-Reload `[F5]` en esta fase (se construyen en la **Fase 06**).
- **NO** bloquear el gameplay esperando assets de IA: cualquier invocación sin sprite debe dibujar un fallback cómico vectorial (`drawProceduralFallbackSummon`: nube caricaturesca o estrella mágica).
- **NO** saturar la pantalla con múltiples banners ni poner screen shake agresivo (tope estricto `shakeMagnitude <= 11.0`, `duration <= 0.36`, y toggleable mediante `setShakeEnabled`).

### Mapa Visual de Carriles Zero-Overlap (1280×720)

```text
y=0   ┌───────────────────────────────────────────────────────────────────────┐
      │ BARRA SUPERIOR HUD (0..54 px) — Zona prohibida para VFX/Globos        │
y=58  ├───────────────────────────────────────────────────────────────────────┤
      │ CARRIL 1 (Cielo Alto, y=108, cx=640): [ ★ ¡COMBO ELECTRO-CHARCO! ★ ]  │
      │ CARRIL 2 (Globos, y∈[58..148]):                                       │
      │   Pudú (px+10, py-148)        Rival (ex-55, ey-210) -> esquiva combo  │
      ├───────────────────────────────────────────────────────────────────────┤
      │ CARRIL 3 (Clima aéreo, y≈ey-178 ≥ 96):       ☁ Nube de lluvia         │
      │                                              ┆ ┆ ┆ (aire libre)       │
      │ CARRIL 4 (Daño / Crítico, arriba-der):                  [-135 ¡CRÍT!] │
      │   Vena furia / Sudor (ex-42, ey-102)          (stagger ±44Y / ±176X)  │
      ├───────────────────────────────────────────────────────────────────────┤
      │ ESCENARIO (Pudú izq. / Rival der.) + Overlays de reacción / Combos    │
      │ CARRIL 5 (Suelo, y=ey+8..18): Charco lágrimas · Helado · Banderita 🏳 │
      ├───────────────────────────────────────────────────────────────────────┤
      │ HUD INFERIOR / INPUT DE PROMPT (parte baja)                           │
y=720 └───────────────────────────────────────────────────────────────────────┘
```

---

## 2. Modo Assets: ¿Ya tengo sprites/música o los incorporo después?

Esta fase está diseñada para **avanzar a máxima velocidad sin esperar al equipo de arte ni audio**:

| Escenario de tu equipo | Qué hacer durante la Fase 05 | Qué pasa después (Fase 06) |
| :--- | :--- | :--- |
| **A. Ya tenemos sprites de rivales/gags y/o SFX listos** | Coloca los PNG en `assets/sprites/encounters/` y `assets/sprites/gags/` (y WAV en `assets/audio/`). `BattleFX` leerá automáticamente `spriteObj.diff` (o `pair.diff`) con `litShaderFn`, y `VictoryAlbum` renderizará los retratos pixel-art nítidos (`nearest`). | En Fase 06 solo generas sus mapas normales `_n.png` en lote y calibras escalas/offsets con `[F2]` + `[F5]`. |
| **B. Todavía NO tenemos sprites/SFX (usamos placeholders)** | ¡Cero bloqueo! `BattleFX` usa `drawProceduralFallbackSummon` (nube o estrella mágica vectorial) y los 6 Super-Combos + 5 Finales Cómicos son **100% vectoriales/procedurales en LÖVE2D**. `VictoryAlbum` usa `drawLockedSilhouetteFallback` si falta un sprite, y los `audio:play(...)` están protegidos con chequeos seguros (`audio and type(audio.play) == "function"`). | En Fase 06 copias los sprites definitivos del artista (o corres el generador IA en lote), pulsas `[F5]` y todo cobra vida al instante sin tocar una línea de `battle_fx.lua` ni `victory_album.lua`. |

> **Regla de oro de desacople**: `battle_fx.lua` y `victory_album.lua` nunca cargan rutas hardcodeadas de disco para sprites; siempre reciben `spriteObj` / `enemySprites` desde `main.lua`, y toleran `nil` sin crashear jamás.

---

## 3. División Codex vs Astra + Subagentes de esta Fase

| Rol | Herramienta | Propiedad de archivos (sin pisarse) | Responsabilidad principal |
| :--- | :--- | :--- | :--- |
| **Orquestador Principal** | **Codex** | `main.lua`, `battle_hud.lua` (solo hooks de integración) | Lanza los 3 subagentes en paralelo, verifica contratos entre módulos y cablea `battle_fx` + `victory_album` al ciclo de batalla y al HUD. |
| **Subagente 5A — Core VFX & Carriles Zero-Overlap** | **Subagente Codex** | `battle_fx.lua` (Parte 1: constructor, 16+ partículas, `launchSummon`, `triggerImpact`, props persistentes, `spawnFloatingText` con stagger, `drawSpeechBubbles`, `drawBackLayer`, `drawSummonsAndProps`, `drawReactionOverlay`, `drawFrontParticles`, `collectLights`) | Implementa toda la arquitectura de carriles matemáticos, hit-stop, screen shake suave, contornos `4 px` y luces dinámicas. |
| **Subagente 5B — Espectáculo de Combos & Finales Cómicos** | **Subagente Codex** | `battle_fx.lua` (Parte 2: `COMBO_THEMES`, `triggerComboSpectacle`, `drawComboSpectacle` para los 6 super-combos, `startDefeatFinale`, `getDefeatTransform`, `drawDefeatFinaleOverlay` para los 5 finales + helpers `drawSurrenderFlag`, `drawFacetedIceCube`, `drawSpinningDustCloud`) | Implementa las 6 secuencias teatrales de Super-Combo y los 5 finales cómicos coordinados con el transform del rival. |
| **Subagente 5C — Álbum de Locuras (`[J]`)** | **Subagente Codex** | `victory_album.lua` | Implementa el modal 3×3 estilo *Final Fantasy*, truncado UTF-8 seguro, tarjetas bloqueadas/desbloqueadas, hit-testing para revancha y persistencia dual en `victory_album.json`. |
| **Director Visual & QA Zero-Overlap** | **Astra** | Solo lectura + reporte de ajustes / capturas | Audita en vivo (o sobre capturas de combos y finales) que **ningún elemento se solape**, revisa ritmo de hit-stop/pop-in, contraste tipográfico en español y calidad cómica de los 5 finales. |

> **Nota sobre edición concurrente en `battle_fx.lua`**: para evitar conflictos entre 5A y 5B, Codex debe pedir a **5B** escribir inicialmente un módulo auxiliar `battle_fx_spectacles.lua` (o esperar la interfaz base de 5A y fusionar limpiamente) o que 5B exporte `{ COMBO_THEMES, normalizeComboType, drawComboSpectacle, computeDefeatTransform, drawDefeatFinaleOverlay, drawDefeatBackLayer }` y `battle_fx.lua` lo requiera — así ambos subagentes corren **100% en paralelo** sin tocar el mismo archivo.

---

## 4. Prompt Maestro para Codex (Copiar y Pegar — Orquestación con Subagentes)

```text
Actúa como Tech Lead de Pudú Fantasy (LÖVE2D 11.5 / Lua) ejecutando la FASE 05: VFX Zero-Overlap, 6 Super-Combos, 5 Finales Cómicos y Álbum de Locuras ([J]).

CONTEXTO ACTUAL:
Ya tenemos funcionando el bucle de batalla por turnos, el ritual de flechas, el cliente IA y el escenario HD-2D con StageRenderer.getBattleAnchors(w, h) y pipeline de luces dinámicas.

ESTRATEGIA DE PARALELISMO (LANZA 3 SUBAGENTES EN PARALELO SIN COLISIONAR ARCHIVOS):
1. Subagente 5A: crea `battle_fx.lua` (motor de partículas con 16+ efectos, invocaciones con 6 estilos de entrega, máx. 3 props persistentes, carriles espaciales Zero-Overlap para clima aéreo / globos / daño flotante con stagger de 6 pasadas y outline 4px `#100818`, hit-stop, shake suave <= 11px y `collectLights(out)`). Debe delegar las tablas/dibujo de super-combos y finales al módulo `battle_fx_spectacles.lua` con fallback seguro si aún no existe.
2. Subagente 5B: crea `battle_fx_spectacles.lua` con los 6 Super-Combos (`combo_electro`, `combo_deep_freeze`, `combo_steam_sauna`, `combo_slip_slide`, `combo_fire_boom`, `combo_chaos`) + sus temas, sonidos y geometría vectorial, y los 5 Finales Cómicos de derrota (`crying`, `scared`/`chased`, `frozen`, `happy_pacified`, y K.O. clásico con estrellas + bandera blanca), exportando `computeDefeatTransform(finale)`, `drawComboSpectacle`, `drawComboBanner`, `drawDefeatBackLayer`, `drawDefeatFinaleOverlay`.
3. Subagente 5C: crea `victory_album.lua` con la galería modal 3×3 "ÁLBUM DE LOCURAS" estilo ventana Final Fantasy azul real biselada, persistencia dual en `victory_album.json`, tarjetas bloqueadas (silueta oscura + `?` + bioma) y desbloqueadas (retrato nearest, badges Bioma/COMBO/CRÍTICO/xN, prompt ganador en dorado UTF-8 seguro, resumen y hit-test para revancha directa).

CUANDO LOS 3 SUBAGENTES TERMINEN, TÚ (ORQUESTADOR) INTEGRARÁS EN `main.lua` y `battle_hud.lua`:
1. Instanciar `battleFX = BattleFX.new()` y `album = VictoryAlbum.new(json)`.
2. En el impacto de batalla (`resolveImpact` o equivalente):
   - Llamar `battleFX:triggerImpact(impactPayload, targetX, targetY - 20, px, py - 20, audio)`.
   - Si `combo_triggered ~= "none"`, llamar `battleFX:triggerComboSpectacle(comboType, comboName, targetX, targetY - 20, audio)`.
   - Si el rival es `nino_helado` y reacciona con lluvia/fuego/llanto/mojado, depositar prop persistente de helado derretido en suelo (`targetX - 58, targetY + 12`).
3. En `triggerVictory()`:
   - Llamar `battleFX:startDefeatFinale(Game.enemyReaction, ex + tr.offsetX, ey + tr.offsetY)`.
   - Llamar `album:recordVictory(enc.id, { prompt, summonName, comboName, isCritical, narrator, reaction, turns })`.
   - Disparar lluvia de confeti y sparkles.
4. En el render de batalla (`love.draw`):
   - Aplicar `battleFX:getDefeatTransform()` (`dx, dy, rot, scaleX, scaleY, alpha, flashWhite`) al sprite del rival.
   - Dibujar `battleFX:drawBackLayer()` detrás de personajes, `battleFX:drawSummonsAndProps(litShader)` en la capa de mundo, y `battleFX:drawReactionOverlay(...)` sobre el rival.
   - Sumar `battleFX:collectLights(sceneLights)` al arreglo de luces HDR.
   - DESPUÉS del post-proceso/bloom (capa UI nítida): dibujar `battleFX:drawFrontParticles(fonts)`, y dibujar `battleFX:drawSpeechBubbles(...)` SOLO cuando `battlePhase ~= "ritual" and battlePhase ~= "victory" and battlePhase ~= "defeat"`.
5. En `battle_hud.lua` e input (`main.lua`):
   - Agregar botón clicable en el HUD para abrir el Álbum (`Álbum [J] (X/9)`).
   - Mapear tecla `j` a `album:toggle()`, `escape` cierra el álbum si está abierto, y en `love.mousepressed` dar prioridad 0 a `album:hitTest(mx, my)`: `"close"` cierra, `"clear"` limpia, `"card"` cierra y llama `enterBattleArenaImmediate(encIndex, false)` para revancha instantánea, y clic fuera del modal cierra.
6. Agregar flags CLI temporales de verificación rápida (`--demo-combo=combo_electro`, `--demo-finale=crying`, `--open-album`) o verificar con pruebas de carga sintáctica (`luac -p` / ejecución de LÖVE) que no haya ningún error nil ni crash en los 6 combos, 5 finales y álbum.

Entrega un resumen con archivos creados/editados, contratos exportados y cómo probar cada efecto.
```

---

## 5. Prompts Individuales por Subagente

### Subagente 5A — Motor VFX y Carriles Espaciales Zero-Overlap (`battle_fx.lua`)

```text
Crea el archivo `battle_fx.lua` para Pudú Fantasy (LÖVE2D 11.5).

REQUISITOS DE ARQUITECTURA ZERO-OVERLAP (ESTRICTOS):
1. Constructor `BattleFX.new()` y `BattleFX:clear()`. Tope `MAX_PERSISTENT_PROPS = 3`, `MAX_PARTICLES = 420`.
2. Control de cámara/tacto: `setShakeEnabled(bool)`, `getShakeOffset()`, `isHitStopped()`, `triggerShake(mag, dur)` con tope suave anti-mareo (`mag <= 11.0`, `dur <= 0.36`), `hitStopTimer` (`0.08s` normal, `0.10s` super-combo) y flash sutil de impacto.
3. `spawnParticles(kind, x, y, count)` soportando los 16+ tipos: `rain`, `snow`, `fire`, `splash`, `hearts`, `tears` (arcos gemelos a ambos lados de los ojos), `steam`, `flash`, `confetti`, `stink`, `mud`, `music`, `explosion`, `wind`, `bubbles`, `stars`, `dust` (en `backParticles`), `sweat` y `sparkles` (default).
4. `launchSummon(result, spriteObj, startX, startY, targetX, targetY, audio)` soportando los 6 estilos de entrega: `overhead_weather`, `drop_from_sky`, `throw_arc`, `charge_across`, `pop_underneath`, `buff_pudu`, con fallback vectorial cómico (`drawProceduralFallbackSummon`) si `spriteObj` es nil.
5. `triggerImpact(result, targetX, targetY, puduX, puduY, audio)`:
   - Emite partículas según `result.particle_fx`.
   - Coloca el número de daño principal en el carril arriba-derecha del rival: `dmgTextX = exTarget + 86`, `dmgTextY = eyTarget - 118` (sumando `+52` en X si es `¡CRÍTICO!`, `+12` si es normal) para dejar 100% libre el rostro del rival y las nubes aéreas.
   - Si `result.keep_prop_on_stage`:
     - Clima aéreo (`overhead_weather` o `prop_anchor == "above_enemy"`): `py = math.max(96, eyTarget - 178)` con offsets horizontales `{ 0, -24, 24 }`.
     - Suelo (`pop_underneath` o `ground_enemy`): `py = eyTarget + 18`.
6. `spawnFloatingText(text, x, y, color, scale, isCrit)`:
   - Algoritmo Anti-Overlap Staggering de hasta 6 pasadas: si existe otro texto con `abs(other.x - fx) < 170` y `abs(other.y - fy) < 42`, empuja `fy = other.y - 44` (si `>= 74`), y si toca el borde superior desplaza `fx` horizontalmente `±176 px` dentro de `[130, sw - 135]`.
   - En `drawFrontParticles(fonts)`: renderiza cada texto con pop `easeOutBack`, sombra inferior, anillo precomputado de outline grueso `4 px` color `#100818` (`OUTLINE_RING_4PX`), y aura dorada aditiva si `isCrit == true`.
7. `setSpeechBubble(who, text, duration, style)` y `drawSpeechBubbles(puduX, puduY, enemyX, enemyY, fonts)`:
   - Rival en `(enemyX - 55, enemyY - 210)` con `by` clamped en `[58, 148]`.
   - Si `self.activeCombo` está activo y el globo invade el banner superior (`bx < sw*0.5 + 225` y `by < 144` y `by+bh > 74`), desplaza `bx = sw*0.5 + 225` (si cabe) o `by = 150`.
   - Pudú en `(puduX + 10, puduY - 148)`.
   - Estilos: `normal`, `shout` (puntiagudo), `cry` (celeste con gotas), `laugh`, `think` (círculos de pensamiento).
8. `drawReactionOverlay(enemyState, enemyX, enemyY, time)`:
   - Reacciones visuales: `crying`, `dizzy`, `angry` (vena en `ex - 42, ey - 102`, arriba-izquierda para no tocar daño), `scared`/`shocked` (gota sudor en `ex - 42, ey - 94`), `frozen`, `wet`, `laughing`, `happy_pacified`, `embarrassed`, `chased`, `splatted`.
   - Si existe `self.defeatFinale`, sincroniza posición con `getDefeatTransform()` y omite overlays base cuando `alpha < 0.15` o `dx > 180` (rival huyendo) o cuando el finale ya dibuja hielo/estrellas.
9. Delega a `pcall(require, "battle_fx_spectacles")` para:
   - `triggerComboSpectacle(comboType, comboName, targetX, targetY, audio)`
   - `startDefeatFinale(reaction, enemyX, enemyY)` y `getDefeatTransform()`
   - Dibujo de back-layer del finale, overlay de combo, overlay de finale y banner de combo en carril superior (`cx = sw * 0.5, cy = 108`).
10. `collectLights(out)` devolviendo luces HDR para la invocación activa, props persistentes, super-combo activo y hasta 48 micro-partículas luminosas (`fire`, `explosion`, `flash`, `sparkles`, `stars`).

Asegura que el código no tenga globals accidentales, restaure blendMode/lineWidth/font/color al salir de cada `draw*` y pase `luac -p battle_fx.lua` (si existe `luac`).
```

### Subagente 5B — 6 Super-Combos Visuales y 5 Finales Cómicos (`battle_fx_spectacles.lua`)

```text
Crea el archivo `battle_fx_spectacles.lua` para Pudú Fantasy (LÖVE2D 11.5), que será requerido por `battle_fx.lua`.

DEBE EXPORTAR UNA TABLA `Spectacles` CON:
1. `COMBO_THEMES` y `normalizeComboType(comboType)` para exactamente los 6 Super-Combos:
   - `combo_electro`: defaultName `"¡COMBO ELECTRO-CHARCO!"`, paleta amarilla/cian, `shakeMag = 9.5`, `sfx1 = "sfx_camera_flash"`, `sfx2 = "parry_clash"`.
   - `combo_deep_freeze`: defaultName `"¡COMBO HIELO TOTAL!"`, paleta hielo/cian, `shakeMag = 7.5`, `sfx1 = "chime_3"`, `sfx2 = "bash_impact"`.
   - `combo_steam_sauna`: defaultName `"¡COMBO SAUNA EXTREMO!"`, paleta crema/rosa cálido, `shakeMag = 7.0`, `sfx1 = "water_rush"`, `sfx2 = "sfx_horn"`.
   - `combo_slip_slide`: defaultName `"¡COMBO RESBALÓN TURBO!"`, paleta oro/turquesa, `shakeMag = 7.2`, `sfx1 = "sfx_boing"`, `sfx2 = "sfx_rimshot"`.
   - `combo_fire_boom`: defaultName `"¡COMBO SUPER-EXPLOSIÓN!"`, paleta fuego/naranja, `shakeMag = 10.5`, `sfx1 = "bash_impact"`, `sfx2 = "rock_fall"`.
   - `combo_chaos`: defaultName `"¡COMBO CAOS TOTAL!"`, paleta arcoíris/violeta, `shakeMag = 9.0`, `sfx1 = "sfx_spell_unleash"`, `sfx2 = "sfx_rimshot"`.
   - `normalizeComboType` reconoce substrings en español/inglés (`electro/rayo`, `freeze/hielo`, `steam/sauna/vapor`, `slip/slide/resbal`, `fire/boom/explo`) y cae a `combo_chaos`.

2. `spawnComboBurst(fx, kind, tx, ty)`: dispara las ráfagas iniciales de partículas en `fx:spawnParticles(...)` apropiadas a cada uno de los 6 combos (y emisión continua en `updateCombo(fx, c, dt)` si aplica).

3. `drawComboSpectacle(c, t)` (espectáculo en espacio del rival, duración 2.2s con fade suave al final):
   - `combo_electro`: rayo principal quebrado desde `y = -12` hasta el rival + 2 ramificaciones laterales (3 capas: brillo aditivo cian 14px, núcleo amarillo 6.5px, filamento blanco 2.4px) + silueta estroboscópica en zigzag alrededor del rival + anillo eléctrico en el suelo.
   - `combo_deep_freeze`: prisma/cubo de hielo facetado translúcido (`drawFacetedIceCube`) con rebote `easeOutBack`, caras biseladas, líneas diagonales blancas especulares, destellos en esquinas y 6 copos cristalinos orbitando.
   - `combo_steam_sauna`: 9 nubes densas ascendentes de vapor blanco y rosa cálido + 4 anillos de calor brillantes subiendo.
   - `combo_slip_slide`: 6 cintas espirales estilo tornado rodeando al rival + 5 estrellas doradas de mareo orbitando en `cy - 168`.
   - `combo_fire_boom`: explosión starburst cómica de 14 puntas (naranja exterior + núcleo dorado) + onda expansiva aditiva + 4 anillos ascendentes de humo de hollín.
   - `combo_chaos`: 12 rayos arcoíris rotativos en modo aditivo + 2 anillos octogonales contrarrotativos.

4. `drawComboBanner(c, fonts, outlineRing4px, critGlowOffsets)`:
   - Dibuja el banner en el carril cielo alto (`cx = sw * 0.5, cy = 108`), cinta diagonal con sombra, borde `#100818` + borde brillante del tema, destellos de 4 puntas en los extremos, auto-escala para textos largos (`maxAllowedW = min(540, sw - 260)`) y outline `4 px` ultra-legible.

5. Sistema de los 5 Finales Cómicos de Derrota:
   - `spawnFinaleBurst(fx, reaction, ex, ey)` y `updateFinale(fx, f, dt)` (emite partículas periódicas suaves: lágrimas continuas en `crying`, corazones en `happy_pacified`, copos en `frozen`).
   - `computeDefeatTransform(f)` devolviendo `{ dx, dy, rot, scaleX, scaleY, alpha, flashWhite }`:
     1. `crying`/`sad`: se desploma (`scaleY -> 0.88`, `scaleX -> 1.06`, `dy -> +6`) con temblor de sollozo.
     2. `scared`/`chased`/`panicked`: sobresalto `0..0.14s`, luego sale disparado a la derecha (`dx: 0 -> 460`) con saltos frenéticos y fade-out al salir de pantalla.
     3. `frozen`: escalofrío `0..0.22s`, luego inmóvil dentro del bloque de hielo.
     4. `happy_pacified`/`pacified`: rebote alegre continuo (`dy = -abs(sin)*10`) y balanceo.
     5. Default / `dizzy` / `splatted` / `defeated`: caída cómica de lado (`rot -> 0.24`, `dx = 10`, `dy = 6`).
   - `drawDefeatBackLayer(f, t)`: para `crying`/`sad`, dibuja el **charco creciente de lágrimas** a los pies (`rx: 22 -> 76`, `ry: 7 -> 23`) con brillo especular y onda expansiva animada.
   - `drawDefeatFinaleOverlay(f, t)`:
     1. `crying`/`sad`: **banderita blanca ondeante** (`drawSurrenderFlag`) en `(ex + 64, ey + 2)`.
     2. `scared`/`chased`/`panicked`: **nube de polvo giratoria Looney Tunes** (`drawSpinningDustCloud`) en `(ex, ey - 24)` con espirales y líneas de velocidad a la derecha.
     3. `frozen`: bloque de hielo cristalino persistente (`drawFacetedIceCube`) en `(ex, ey - 74)`.
     4. `happy_pacified`/`pacified`: 4 corazones orbitando + 3 estrellas doradas aditivas.
     5. Default / K.O. clásico: 4 estrellas doradas orbitando en `(ex + 14, ey - 168)` + banderita blanca en `(ex + 66, ey + 2)`.

Todo 100% autocontenido en LÖVE2D sin assets externos requeridos y sin contaminar estado gráfico.
```

### Subagente 5C — Galería Persistente 3×3 Álbum de Locuras (`victory_album.lua`)

```text
Crea el archivo `victory_album.lua` para Pudú Fantasy (LÖVE2D 11.5): la galería persistente 3×3 "ÁLBUM DE LOCURAS".

ESPECIFICACIÓN EXACTA:
1. API pública:
   - `VictoryAlbum.new(jsonMod)` — resuelve `json` (recibido o `require("json")`), carga `victory_album.json` al iniciar.
   - `recordVictory(encId, entry)` — guarda/actualiza `{ prompt, summonName, comboName, isCritical, narrator, reaction, turns, timestamp, count = prevCount + 1 }` y persiste inmediatamente.
   - `getEntry(encId)`, `countUnlocked()`, `clear()` (limpia y guarda).
   - `toggle()`, `isOpen()`, `close()`, `containsPoint(mx, my)`, `hitTest(mx, my)` (retorna `"close" | "clear" | "card"`, más `encIndex` como payload para `"card"`).
   - `draw(encountersList, enemySprites, fonts, w, h)`.

2. Persistencia dual (`victory_album.json` con `{ version = 1, entries = {...} }`):
   - Al guardar: escribe tanto en `love.filesystem.write("victory_album.json", encoded)` como en el directorio externo del proyecto / ejecutable fused (`getExternalAlbumPath()` con `io.open(..., "w")`), con fallback a ruta relativa.
   - Al cargar: intenta primero ruta externa, luego `love.filesystem.read`, luego ruta relativa, normalizando todos los campos para tolerar JSON incompleto o corrupto sin crashear.

3. Estética RPG clásica (Final Fantasy azul real biselado):
   - Fondo semitransparente oscuro a pantalla completa (`alpha = 0.76`).
   - Ventana modal centrada (`mw = clamp(sw - 80, 860, 1100)`, `mh = clamp(sh - 68, 476, 636)`) con `drawFFWindow` (degradado azul real en 6 franjas, sombra, doble borde oscuro + plateado/dorado y 4 remaches dorados en esquinas).
   - Encabezado: `"ÁLBUM DE LOCURAS  (X / 9 Rivales Vencidos)"` en dorado + botones `"Limpiar"` y `"[X]"` con estado hover.
   - Grilla 3×3 (`cols = 3, rows = 3`) con tarjetas clicables para los 9 encuentros.

4. Diseño de tarjetas:
   - Retrato cuadrado a la izquierda con fondo temático del bioma (`bosque`, `desierto`, `costa`, `ciudad`), número de slot `#1..#9` en esquina superior izquierda y extracción compatible tanto con sprites simples (`diff`/`image`) como con spritesheets con quads (`isSheet + quads.grid`). Siempre fuerza filtro `nearest` al dibujar el retrato y restaura el filtro previo.
   - **Tarjeta bloqueada**: sprite dibujado en silueta oscura `(0.05, 0.08, 0.18, 0.92)` (o fallback silueta si no hay imagen) + signo `"?"` centrado, título `"???"`, pill del bioma y pista sutil `"Haz clic para desafiar"`.
   - **Tarjeta desbloqueada**: retrato a color con sombra de contacto, nombre del rival, fila de badges compactos (`Bioma`, badge cian `COMBO` si `comboName ~= ""`, badge dorado `CRÍTICO` si `isCritical`, y `xN` si `count > 1`), cita dorada `"Con: '<prompt>'"` con wrap limpio de hasta 2 líneas, y 1 línea de memoria cómica (`narrator` o turnos).
   - Implementar `truncateText(font, text, maxW)` **UTF-8 seguro** (retrocediendo por codepoint completo para jamás cortar tildes `áéíóú` ni `ñ` en español).
   - Pie del modal: `"Haz clic en cualquier rival para ir directo a la revancha  ·  [J] o [ESC] para cerrar"`.
```

---

## 6. Prompt para Astra (Auditoría Visual Zero-Overlap & Polish Artístico/Sonoro)

Usa este prompt con **Astra** justo después de que Codex integre los módulos (idealmente adjuntando 3–5 capturas de pantalla: un impacto normal, un Super-Combo con crítico + nube + globo, un final cómico `crying` o `scared`, y el Álbum `[J]` con tarjetas mezcladas bloqueadas/desbloqueadas):

```text
Actúa como Art & VFX Director (Astra) auditando la FASE 05 de Pudú Fantasy (VFX Zero-Overlap, 6 Super-Combos, 5 Finales Cómicos y Álbum de Locuras).

Revisa `battle_fx.lua`, `battle_fx_spectacles.lua`, `victory_album.lua`, la sección de render de `main.lua` y las capturas adjuntas con esta lista de auditoría quirúrgica:

1. AUDITORÍA ESTRICTA ZERO-OVERLAP (TOLERANCIA CERO):
   - En el peor caso simultáneo (Banner de Super-Combo arriba + Globo del rival + Nube de lluvia en `above_enemy` + `"-135 ¡CRÍTICO!"` + barra de HP del rival), ¿algún texto o elemento pisa a otro o tapa la cara del rival?
   - Durante `battlePhase == "ritual"` y `"victory"` / `"defeat"`, ¿están 100% suprimidos los globos de diálogo?
   - Si salen 2 o 3 textos flotantes seguidos (daño + efecto + autogol), ¿el staggering de `spawnFloatingText` los separa limpiamente sin salirse del viewport 1280×720?

2. LECTURA CÓMICA Y "JUICE" DE LOS 6 SUPER-COMBOS Y 5 FINALES:
   - ¿Cada uno de los 6 Super-Combos (`combo_electro`, `combo_deep_freeze`, `combo_steam_sauna`, `combo_slip_slide`, `combo_fire_boom`, `combo_chaos`) se distingue en menos de 0.3 segundos sin leer el texto?
   - ¿El contorno de 4px `#100818` de los números de daño y el banner de combo mantiene contraste AAA sobre fondos claros (Costa/Desierto) y oscuros (Noche/Oficina)?
   - En los 5 finales de derrota (`crying`, `scared`, `frozen`, `happy_pacified`, K.O. clásico), ¿el ritmo del hit-stop, la escala/rotación de `getDefeatTransform()` y los props finales (charco, banderita blanca, nube Looney Tunes, cubo de hielo, corazones, estrellas) se sienten expresivos y no dejan íconos huérfanos cuando el rival huye?

3. POLISH DEL ÁLBUM DE LOCURAS ([J]):
   - ¿El truncado UTF-8 respeta tildes (`¡`, `á`, `é`, `í`, `ó`, `ú`, `ñ`) en nombres, prompts y narraciones largas?
   - ¿La jerarquía visual entre tarjetas bloqueadas (misterio oscuro `?`) y desbloqueadas (trofeo dorado brillante) invita a completar los 9/9?
   - ¿Los retratos pixel-art se ven nítidos (`nearest`) sin recortarse ni deformarse dentro del marco cuadrado?

ENTREGA TU AUDITORÍA EN 3 BLOQUES CORTOS:
- [CRÍTICO / BLOQUEANTE]: cualquier solapamiento, bug UTF-8 o error de capa que haya que corregir antes de pasar a Fase 06 (con archivo, línea y cambio exacto sugerido).
- [MEJORAS DE ALTO IMPACTO < 15 MIN]: retoques de color, timing, curvas easing o contraste que eleven el factor "wow" para el jurado.
- [VEREDICTO]: APROBADO PARA FASE 06 / REQUIERE PASE DE CORRECCIÓN.
```

---

## 7. Gate de Iteración en Equipo (Playtest de 5 min + Definition of Done)

Antes de cerrar la Fase 05 y pasar a la Fase 06, todo el equipo (programador + artista + diseñador) realiza este **playtest cronometrado de 5 minutos**:

### Guion de Playtest (5 minutos)
1. **Minuto 0–1 (Prueba de estrés Zero-Overlap)**: Entra contra el *Niño con Helado* (`nino_helado`), lanza `"nube de lluvia"` (queda la nube flotando alto + helado derretido en el suelo + globo llorando) y en el siguiente turno lanza `"rayo"` para disparar `combo_electro` + `¡CRÍTICO!`. **Congela mentalmente o toma captura**: verifica que banner superior, globo del rival, nube, cara del rival, daño crítico y helado en el suelo estén cada uno en su carril sin pisarse.
2. **Minuto 1–3 (Tour de los 6 Super-Combos y 5 Finales)**: Dispara en modo prueba/mock (o prompts rápidos) al menos 1 ejemplo de cada uno de los 5 finales (`crying`, `scared`, `frozen`, `happy_pacified`, y K.O. clásico). Verifica que cuando el rival huye (`scared`), desaparece hacia la derecha dejando la nube giratoria sin íconos flotando encima.
3. **Minuto 3–4 (Álbum de Locuras `[J]` + Persistencia)**: Tras vencer al menos 2 rivales (uno con crítico/combo y uno normal), pulsa `[J]` y también haz clic en el botón del HUD. Verifica las tarjetas desbloqueadas con tu prompt ganador exacto, haz clic en una tarjeta para comprobar la revancha directa, **cierra y vuelve a abrir el juego** para confirmar que `victory_album.json` persistió intacto.
4. **Minuto 4–5 (Resiliencia sin assets y rendimiento)**: Prueba una invocación que no tenga PNG (debe salir el fallback vectorial sin error) y verifica que los FPS sigan fluidos a 60 FPS incluso con 3 props activos + partículas + luces HDR.

### Definition of Done (Checklist de salida de Fase 05)
- [ ] **Zero-Overlap verificado**: cero colisiones entre banner de combo (`y = 108`), globo rival (`y ∈ [58, 148]` con esquive de combo), nube climática (`ey - 178`), daño flotante (staggering 6 pasadas + outline 4px) y props de suelo.
- [ ] **Silencio de globos**: los globos no se dibujan durante `ritual`, `victory` ni `defeat`.
- [ ] **6 Super-Combos operativos**: `combo_electro`, `combo_deep_freeze`, `combo_steam_sauna`, `combo_slip_slide`, `combo_fire_boom` y `combo_chaos` se disparan, iluminan el escenario (`collectLights`) y suenan sin error.
- [ ] **5 Finales Cómicos operativos**: `crying` (charco creciente + lágrimas + bandera blanca), `scared`/`chased` (huida cohete + nube polvo), `frozen` (bloque de hielo), `happy_pacified` (corazones) y K.O. clásico (estrellas + bandera blanca).
- [ ] **Álbum de Locuras (`[J]`) completo**: grilla 3×3 azul real *Final Fantasy*, tarjetas bloqueadas `?` + desbloqueadas con badges y prompt ganador en español UTF-8 seguro, botón HUD, revancha con 1 clic y persistencia verificada en `victory_album.json` tras reiniciar.
- [ ] **Veredicto de Astra**: sin hallazgos `[CRÍTICO / BLOQUEANTE]` pendientes.
