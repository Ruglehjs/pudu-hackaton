# Recetario de Prompts de Iteración Rápida con el Equipo (Codex + Astra)

> **Cuándo usar este recetario:** **ENTRE fases** (o tras una sesión rápida de playtesting con el equipo), cuando alguien dice *"esto se siente un poco duro"*, *"ese texto se tapó"*, *"el artista ya dibujó un rival nuevo"* o *"faltan 30 minutos y hay que arreglar un bug sin romper nada"*.  
> **El ciclo de iteración de 5 minutos:**
> 1. **Jugar 60 s** y capturar el problema con **`[F12]`** (o flag `--screenshot=...`).
> 2. **Si es visual/UX:** pegar la captura en **Astra** para diagnóstico preciso.
> 3. **Aplicar cirugía acotada en Codex** con la receta exacta de abajo (respetando `AGENTS.md`).
> 4. **Re-capturar y validar** (`exit code 0`, cero overlaps, cero tofu `[X]`).

---

## Receta 1 — Ajustar "Game Feel" de Cámara y Movimiento en el Mapa Diagonal `↗`

**Cuándo usarla:** El Pudú camina muy lento/rápido en el Overworld, se traba en los bordes, el paneo entre habitaciones se siente brusco o la cámara tarda demasiado/muy poco en cambiar de cuarto.  
**Archivos implicados:** `main.lua` (`updateExplore`), `stage_renderer.lua` (`screenVecToIso`, `ROOM_SPACING`, `updateExploreCamera`, `snapCameraToChunk`, `camZoom`).

### Prompt Copy-Paste para Codex

```markdown
Lee AGENTS.md (en especial R7: cámara calma room-snapped en el mapa diagonal ↗).
Ajusta únicamente el game feel de exploración en `main.lua` y `stage_renderer.lua` según este feedback del equipo:
- Sensación actual del problema: [EJ: "El Pudú se siente lento al subir en diagonal y la cámara cambia de cuarto un poco tarde"]
- Objetivo deseado: [EJ: "Subir velocidad de 6.2 a 7.4 en `StageRenderer.screenVecToIso`, bajar umbral de cambio de cuarto de `du > 7.4` a `du > 6.6` y suavizar la duración del paneo smoothstep a 0.42 s"]

Restricciones obligatorias:
1. NUNCA conviertas la cámara en seguimiento continuo frame-a-frame: dentro de la habitación activa la cámara DEBE seguir 100% quieta (cero mareo).
2. Conserva el sliding limpio en colisiones (`isWalkable(candU, candV)` -> probar eje U -> probar eje V) y las 8 direcciones de sprite (`puduFacingRow`).
3. No cambies el recorrido `u = 0..118` ni las posiciones de los 9 rivales salvo que se indique.

Verificación:
- Ejecuta `./run.sh --mode=explore --biome=bosque --print-perf --screenshot=screenshots/iter_gamefeel.png --quit-after=2.0` y confirma `exit code 0`.
- Reporta los valores exactos antes y después (velocidad, `du/dv` threshold, duración de paneo y `camZoom`).
```

---

## Receta 2 — Arreglar Solapamiento Visual de Textos, Burbujas o Efectos (Astra -> Codex)

**Cuándo usarla:** Un globo de diálogo choca con las flechas del ritual, un número `-135 ¡CRÍTICO!` tapa la cara del rival, o una píldora de estado choca con el HUD inferior.  
**Archivos implicados:** `battle_hud.lua`, `battle_fx.lua`, `spell_ritual.lua`, `main.lua` (globo de anticipación).

### Paso A — Prompt Copy-Paste para Astra (adjunta la captura `[F12]`)

```markdown
Revisa esta captura `1280×720` de Pudú Fantasy. Detectamos un solapamiento visual en: [DESCRIBIR ZONA, EJ: "el globo de anticipación del rival toca la bandeja de flechas"].

Indícame de forma exacta y accionable para pasarle a Codex:
1. Qué 2 o más elementos están chocando y en qué coordenadas aproximadas (`x, y`).
2. Qué carril de la tabla Zero-Overlap (barra superior `y=10..48`, estado ritual `y>=56`, bandeja flechas `panelY>=126`, anticipación rival `x>=0.58w`, arena `0.65h`, strip inferior `78px`) fue violado.
3. Desplazamiento exacto en píxeles o regla de clamping recomendada para dejar al menos `12–16 px` de aire limpio sin romper el equilibrio visual.
4. Confirma si ves de paso alguna caja tofu `[X]` o halo de bloom quemado en la misma captura.
```

### Paso B — Prompt Copy-Paste para Codex (pega el diagnóstico de Astra)

```markdown
Lee AGENTS.md (R2 cero tofu y R6 tabla de carriles Zero-Overlap).
Corrige este solapamiento visual diagnosticado por Astra:
[PEGAR DIAGNÓSTICO DE ASTRA AQUÍ]

Reglas de cirugía:
- Toca únicamente el módulo responsable (`battle_hud.lua`, `battle_fx.lua`, `spell_ritual.lua` o el bloque de globo de anticipación en `main.lua`).
- Mantén el clamping dependiente de `w, h` (que funcione en `1280×720` y en ventana redimensionada `960×540`).
- Conserva el staggering de 6 pasadas en `battleFX:spawnFloatingText` y nunca reintroduzcas emojis o caracteres fuera de `PTSans.ttc`.

Verificación obligatoria:
- Reproduce exactamente el estado con CLI (ej. `--mode=battle --encounter=[N] --test-ritual` o `--demo-combo=[ID]` o `--auto-prompt="[PROMPT]"`) y guarda `screenshots/iter_overlap_fix.png` con `--quit-after=...`.
- Confirma `exit code 0` y dime la ruta del PNG para re-validarlo con Astra.
```

---

## Receta 3 — Agregar un Nuevo Rival o un Nuevo Bioma de Forma Limpia

**Cuándo usarla:** El equipo quiere añadir un 10.º encuentro hilarante (ej. *"Inspector de Micro"*) o expandir un bioma nuevo manteniendo paridad entre exploración, combate, IA online y modo offline.  
**Archivos implicados:** `encounters.lua`, `stage_renderer.lua` (si hay bioma/tema nuevo), `ai_bridge.py`, `battle_worker.lua`, `main.lua` (`loadAllSprites` si hay props nuevos), `assets/sprites/encounters/<id>.png` (+ `_n.png`).

### Prompt Copy-Paste para Codex

```markdown
Lee AGENTS.md (secciones 2, 3 y 4: contrato JSON de 34 campos y paridad online/offline).
Agrega un nuevo [RIVAL / BIOMA] de forma completamente integrada:

Datos de diseño:
- ID técnico (snake_case sin tildes): `[EJ: inspector_micro]`
- Nombre visible (español): `[EJ: Inspector de la Micro]`
- Bioma asignado y posición `(u, v)`: `[EJ: ciudad, u=102.0, v=0.4]` (o rango `uStart..uEnd` si es bioma nuevo)
- Sprite base: `assets/sprites/encounters/[ID].png` (y `[ID]_n.png`) — escala sugerida `[2.55]`, `maxHp = [100]`
- Personalidad, `introLine` (sin spoilers) y `semiHintLine` (pista sutil solo tras 2 fallos):
  - `introLine`: `"[EJ: ¡Boleto en mano o no pasa nadie por este paradero!]"`
  - `semiHintLine`: `"[EJ: Mmm... a mí solo me ablandan un pase escolar impecable o algo que me haga perder el bus...]"`
- Debilidades cómicas críticas (2 o 3 ideas ejemplo): `[EJ: pase escolar gigante, micro pasando rápido, timbre de bajada]`
- Contraataque propio: nombre, frase, daño (`11–15`) y `enemy_counter_fx` (`flash`/`wind`/`mud`/`tears`/`music`/`stink`).

Checklist obligatorio de integración:
1. `encounters.lua`: agregar la entrada en `Encounters.LIST` (y en `BIOMES` / `STAGE_THEMES` si es bioma nuevo) sin romper los índices existentes.
2. `stage_renderer.lua`: si es bioma nuevo, agregar paleta/decorado y soporte en `getBiomeAt(u)` y el minimapa.
3. `ai_bridge.py`: agregar ficha cómica del rival en el catálogo de contexto para `gemini-2.5-flash` y su lógica en el fallback local Python.
4. `battle_worker.lua`: agregar la misma ficha en `ENCOUNTER_META` y reglas críticas en el motor offline Lua para garantizar 100% paridad sin internet.
5. Verificar que `victory_album.lua` y `director_panel.lua` muestren al nuevo rival sin desbordes.

Verificación:
- Captura en batalla: `./run.sh --mode=battle --encounter=[INDICE_NUEVO] --mock --auto-prompt="[PROMPT_CRITICO]" --screenshot=screenshots/iter_new_rival.png --quit-after=6.0`
- Smoke test offline (puerto cerrado `PUDU_BATTLE_PORT=19999`) con el mismo encuentro y prompt.
- Confirmar `exit code 0` en ambos y mostrar el JSON devuelto (34 campos completos).
```

---

## Receta 4 — Ajustar Humor, Severidad o Velocidad de Respuesta de la IA (`ai_bridge.py`)

**Cuándo usarla:** La IA está demasiado generosa (todo es `¡CRÍTICO!`), demasiado estricta (rechaza ideas divertidas), escribe textos muy largos para las burbujas, o tarda más de 1.2 segundos en responder.  
**Archivos implicados:** `ai_bridge.py`, `battle_worker.lua` (mantener paridad del tono y límites).

### Prompt Copy-Paste para Codex

```markdown
Lee AGENTS.md (sección 4.1: contrato JSON de 34 campos e invariantes de rechazo).
Ajusta el comportamiento del juez cómico en `ai_bridge.py` (y sincroniza lo equivalente en `battle_worker.lua`):

Ajuste requerido por el equipo:
- Tono / humor: [EJ: "Más chispa chilena/latam, remates cortos de máximo 12 palabras para `enemy_speech` y `narrator_text`"]
- Calibración de dificultad: [EJ: "Subir exigencia de `is_critical`: solo dar >= 95 daño si hay causa-efecto clara con el rival o Super-Combo de 2 turnos; ideas simpáticas pero genéricas dan 28-45 daño"]
- Latencia / rendimiento: [EJ: "Asegurar `thinkingBudget=0`, reducir tokens innecesarios del system prompt y agregar los nuevos sinónimos `[PALABRAS]` a `EXISTING_SPRITE_KEYWORDS` para evitar llamadas de imagen redundantes"]

Restricciones:
1. NO alteres los nombres ni tipos de ninguno de los 34 campos en `RESPONSE_SCHEMA`.
2. Mantén bloqueados los intentos de trampa (`OBVIOUS_REJECT_KEYWORDS`), saludos puros y gibberish.
3. Todo texto (`enemy_speech`, `narrator_text`, `anticipation_line`) debe mantenerse libre de emojis y respetando límites UTF-8 seguros para que nunca desborde una burbuja.

Verificación:
- Corre `python3 -m py_compile ai_bridge.py`.
- Ejecuta 5 requests de prueba contra `http://127.0.0.1:18425/battle_prompt` (1 crítico, 1 gag intermedio, 1 combo, 1 trampa, 1 prompt loco) e imprime latencia en ms + `is_critical`, `damage_to_enemy`, `enemy_speech` y `narrator_text`.
```

---

## Receta 5 — Incorporar un Sprite Nuevo del Artista + Generar `_n.png` + Probar con `[F5]`

**Cuándo usarla:** El artista del equipo exportó un PNG nuevo (un rival, un gag, un sombrero o un prop) y quieren verlo iluminado en HD-2D con normal map y recarga en vivo sin reiniciar el juego.  
**Archivos implicados:** `assets/custom/<id>.png` (o `assets/sprites/...`), `tools/sprite_studio.py`, `stage_overrides.json`.

### Prompt Copy-Paste para Codex

```markdown
Lee AGENTS.md (R1 filtro `nearest` + soporte fused/unfused y pipeline de sprites).
El artista entregó un nuevo sprite en: `[RUTA_ORIGEN, EJ: ~/Desktop/gato_nuevo.png]`
Destino deseado: `[EJ: assets/sprites/encounters/gato_guaton.png]` (o `assets/custom/[ID].png` para prueba rápida con `[F5]`).

Ejecuta este pipeline limpio:
1. Inspecciona dimensiones y transparencia del PNG fuente (si viene con fondo magenta sólido en vez de alfa transparente, límpialo usando `tools/sprite_studio.py hero --raw <ruta> --name <id> --max-dim <px>`).
2. Copia/guarda el difuso final en la ruta destino y genera su mapa de normales Sobel en espacio tangente (`<nombre>_n.png`) usando `generate_normal_map(img, strength=2.5, dome_weight=0.50)` de `tools/sprite_studio.py`.
3. Verifica que difuso y `_n.png` tengan **exactamente las mismas dimensiones** (ancho × alto) y modo `RGBA`.
4. Si es un sprite nuevo no registrado aún, agrégalo a `loadAllSprites()` en `main.lua` (y a `VALID_EXISTING_SPRITES` / `EXISTING_SPRITE_KEYWORDS` si es un gag invocable).
5. Toma dos capturas de verificación en `1280×720`: una con `--lighting=dia` y otra con `--lighting=noche` para comprobar que el normal map reacciona bien a la luz dinámica sin halos quemados.

Nota para el artista en vivo:
- Con el juego abierto, pulsa **`[F5]`** para recargar en caliente, abre **`[F2]` -> pestaña Gráfica** para afinar `Escala` y `Offset X/Y`, y pulsa **Guardar Ajustes** (`stage_overrides.json`).
```

---

## Receta 6 — Cambiar la Canción de Batalla y Recalibrar `BPM` y `beatOffset` para el Baile del Pudú

**Cuándo usarla:** El compositor o el equipo consiguió un temazo nuevo para la batalla y el Pudú necesita bailar y rebotar su sombrero al compás exacto sin desfase.  
**Archivos implicados:** `assets/audio/<cancion>.wav` (u `.ogg`), `audio.lua` (`TRACK_META`), `main.lua` (`BeatSync.new(...)`), `tools/build_windows_exe.py` (verificación de inclusión).

### Prompt Copy-Paste para Codex

```markdown
Lee AGENTS.md (R8: baile idle al compás con PLL sobre `source:tell("seconds")`, SIN notas ni mecánica rítmica).
Vamos a cambiar la pista principal de batalla por: `[RUTA_AUDIO, EJ: assets/audio/battle_user_main.wav]`.

Tareas exactas:
1. Analiza el archivo de audio con Python (`wave` / `numpy` o `librosa` si está disponible) para medir:
   - Duración exacta en segundos.
   - `bpm` preciso (si ya lo conocemos: `[EJ: 128.00]`, si no, estímalo con autocorrelación de energía de onsets).
   - `beatOffset` (timestamp en segundos del primer golpe fuerte real para evitar que el Pudú baile a contratiempo).
   - `beats` totales exactos del loop para que `beat_sync.lua` envuelva el loop sin salto de fase.
2. Actualiza `Audio.TRACK_META.user_battle` en `audio.lua` (y el valor por defecto en `BeatSync.new(...)` de `main.lua` si corresponde).
3. Asegúrate de que el nombre del archivo NO coincida con `SKIP_AUDIO_PREFIXES` en `tools/build_windows_exe.py` y que el assert de empaquetado apunte al archivo correcto.
4. Verifica con `./run.sh --mode=battle --encounter=1 --print-perf --quit-after=3.5` que la pista carga sin error de OpenAL, entra en loop limpio y `beatSync` avanza monotónicamente.
5. Reporta `bpm`, `beatOffset`, `beats` y duración exacta; si tras probarlo a oído el baile se siente adelantado/atrasado, ajusta `beatOffset` en pasos de `±0.025 s`.
```

---

## Receta 7 — Crear un Nuevo Super-Combo de 2 Turnos (IA + VFX + Botón Director `[F2]`)

**Cuándo usarla:** El equipo inventó una sinergia divertidísima (ej. `pegajoso` + `viento/plumas` = **`¡COMBO GALLINA EMPLUMADA!`** o `oscuro` + `fuego` = **`¡COMBO FOGATA SORPRESA!`**) y quiere verlo brillar en demo.  
**Archivos implicados:** `ai_bridge.py`, `battle_worker.lua`, `battle_fx.lua`, `director_panel.lua`, `main.lua`.

### Prompt Copy-Paste para Codex

```markdown
Lee AGENTS.md (contrato JSON de 34 campos + paridad online/offline + R6 Zero-Overlap).
Implementa un nuevo Super-Combo de 2 turnos de principio a fin:

Especificación del combo:
- ID técnico: `[EJ: combo_feather_storm]`
- Nombre en pantalla: `[EJ: ¡COMBO TORMENTA DE PLUMAS!]`
- Estado previo requerido en `stage_states`: `[EJ: pegajoso]` (de `VALID_STAGE_STATES`)
- Disparadores en turno 2 (palabras/conceptos): `[EJ: almohada, plumas, ventilador, gallina]`
- Reacción resultante del rival y tag: `enemy_reaction = "[EJ: dizzy]"`, `status_tag = "[EJ: EMPLUMADO]"`
- Frase de anticipación durante ritual: `"[EJ: ¡Espera... estoy todo pegajoso, NO sueltes plumas!!]"`
- Espectáculo visual VFX y colores: `[EJ: remolino blanco y dorado alrededor del rival + explosión de plumas + shake medio + flash suave]`

Implementación en los 5 puntos exactos:
1. `ai_bridge.py`: agregar `[ID]` a `VALID_COMBO_TRIGGERS`, `COMBO_DEFAULT_NAMES`, prompt del sistema y detector local de combos.
2. `battle_worker.lua`: agregar exactamente el mismo `[ID]` en `VALID_COMBO_TRIGGERS`, `COMBO_DEFAULT_NAMES`, `COMBO_DEFAULT_ANTICIPATION` y reglas offline.
3. `battle_fx.lua`: agregar tema y espectáculo visual en `COMBO_THEMES` / `triggerComboSpectacle` / draw del combo (sin tapar textos ni crear halos quemados).
4. `director_panel.lua` + `main.lua`: agregar botón rápido `__COMBO_[CORTO]__` en `QUICK_GAGS` y cablearlo en `handleDirectorAction` y en el flag `--demo-combo=[ID]`.

Verificación obligatoria:
- Captura directa: `./run.sh --mode=battle --encounter=1 --mock --demo-combo=[ID] --screenshot=screenshots/iter_new_combo.png --quit-after=1.8`
- Prueba HTTP y prueba offline (puerto cerrado) verificando que `stage_states=["[ESTADO]"]` + prompt disparador devuelve `combo_triggered="[ID]"`.
```

---

## Receta 8 — Simplificar y Limpiar la UI cuando se Sienta Recargada (Astra -> Codex)

**Cuándo usarla:** Alguien del equipo prueba el juego y comenta *"hay demasiadas cosas en pantalla"* o *"cuesta saber dónde mirar primero"*.  
**Archivos implicados:** `battle_hud.lua`, `director_panel.lua`, `victory_album.lua`.

### Paso A — Prompt Copy-Paste para Astra (adjunta 2 capturas: exploración y batalla)

```markdown
Evalúa estas capturas `1280×720` de Pudú Fantasy como diseñador UI/UX de JRPG modernos (Octopath / Final Fantasy / Mario & Luigi).
El equipo siente que la interfaz está un poco cargada en: [ZONA O MODO].

Propón una **poda minimalista de máximo 4 cambios** que:
1. Mantenga la estética limpia de ventana azul biselada Final Fantasy y el strip inferior `~78px`.
2. Respete estrictamente cero chips de pistas de prompts y cero elementos de mecánica rítmica.
3. Aumente el espacio de respiro alrededor del Pudú, el rival y los efectos HD-2D.
4. Sea 100% implementable en `battle_hud.lua` sin agregar archivos ni fuentes externas.
```

### Paso B — Prompt Copy-Paste para Codex

```markdown
Lee AGENTS.md (R2 cero tofu, R6 carriles Zero-Overlap, R8 sin botones rítmicos, R9 cero chips de pistas).
Aplica esta poda de simplificación UI aprobada por Astra en `battle_hud.lua`:
[PEGAR LOS 3-4 CAMBIOS DE ASTRA]

Restricciones:
- Mantén 100% funcionales todos los hitboxes (`hud:hitTest`) de los botones conservados (`toggle_director`, `toggle_album`, `flee_to_map`, `toggle_music`, `focus_prompt`, `cast_prompt`, `victory_continue`, `battle_rematch`) y el toggle de ocultamiento `[H]`.
- Re-captura `screenshots/iter_ui_clean_explore.png` y `screenshots/iter_ui_clean_battle.png` con `--quit-after=2.0` y verifica `exit code 0`.
```

---

## Receta 9 — Hotfix de Emergencia a 30 Minutos del Cierre (Modo Pánico Seguro)

**Cuándo usarla:** Faltan menos de 30 minutos para el cierre de envíos o para subir al escenario y aparece un bug visible o un crash reproducible. **Prioridad absoluta: NO romper el build estable.**

> [!WARNING]
> **Reglas del Modo Pánico Seguro (últimos 30 minutos):**
> - **PROHIBIDO** tocar `shaders.lua`, `lighting_pipeline.lua`, `RESPONSE_SCHEMA` o refactorizar módulos completos.
> - **OBLIGATORIO** guardar copia de respaldo antes del cambio (`git status` + `git stash` o copia de `dist/PuduFantasy-Windows-x64.zip` a `dist/BACKUP_ESTABLE.zip`).
> - **MÁXIMO 1 archivo** editado por hotfix (o 2 solo si es paridad `ai_bridge.py` + `battle_worker.lua`).

### Prompt Copy-Paste para Codex (Modo Pánico Seguro)

```markdown
⚠️ MODO HOTFIX DE EMERGENCIA (quedan <30 min para el cierre de la hackathon).
Objetivo: aplicar el arreglo MÁS PEQUEÑO, SEGURO Y REVERSIBLE posible. CERO refactors, CERO cambios en shaders/pipeline/esquema JSON.

Síntoma exacto reproducible:
- Comando o pasos que fallan: [EJ: "Al apretar Escape en el Álbum de Locuras se salía de la batalla"]
- Error o captura: [PEGAR STACK TRACE O DESCRIPCIÓN EXACTA]

Protocolo obligatorio:
1. Primero haz un diagnóstico de 3 líneas indicando la causa raíz exacta y el ÚNICO archivo (y rango de líneas) a editar.
2. Aplica un diff quirúrgico mínimo (idealmente < 20 líneas).
3. Ejecuta el smoke test rápido de 60 segundos:
   - Reproducir el caso del bug y confirmar que ya no falla (`exit code 0`).
   - Correr `./run.sh --mode=battle --encounter=1 --mock --auto-prompt="nube de lluvia" --quit-after=6.0` (`exit code 0`).
   - Re-construir el paquete portable (`python3 tools/build_windows_exe.py`) y validar `PUDU_BATTLE_PORT=19999 <LOVE_BIN> dist/PuduFantasy.love --mode=battle --encounter=1 --auto-prompt="nube de lluvia" --quit-after=6.0`.
4. Entrega `git diff --stat` y confirma si el build está listo para entregar.
```

---

## Receta 10 — Checklist Rápido de "Decisión Go / No-Go" para Pasar a la Siguiente Fase

Úsala con todo el equipo al terminar **cada fase** (de Fase 1 a Fase 7). Toma **3 minutos** y evita arrastrar deuda rota hacia la fase siguiente.

### Rúbrica de 10 Puntos (Bloqueantes vs Diferibles)

| # | Criterio de Gate entre Fases | Tipo | Estado |
|---|---|---|---|
| 1 | El juego arranca y cierra limpio con `--quit-after=2.0` (`exit code 0`, cero `[PUDU FANTASY ERROR]`). | **BLOQUEANTE** | `[ ]` |
| 2 | Los flags CLI del contrato (`--mode`, `--encounter`, `--mock`, `--screenshot`, `--quit-after`) siguen funcionando sin regresiones. | **BLOQUEANTE** | `[ ]` |
| 3 | Cero warnings GLSL nuevos y cero llamadas `shader:send` sin `hasUniform` / `Shaders.send`. | **BLOQUEANTE** | `[ ]` |
| 4 | Captura `1280×720` revisada por **Astra** (o 2 integrantes): cero cajas tofu `[X]`, cero flechas deformadas, cero overlap grave. | **BLOQUEANTE** | `[ ]` |
| 5 | Si se tocó IA o encuentros: contrato de 34 campos JSON íntegro y **modo offline (`battle_worker.lua`) funcional sin `ai_bridge.py`**. | **BLOQUEANTE** | `[ ]` |
| 6 | Reglas de diseño intactas: cámara calma room-snapped en `↗`, baile idle sin notas punitivas y cero chips de pistas de prompts. | **BLOQUEANTE** | `[ ]` |
| 7 | Si se agregó un archivo `.lua` nuevo, ya fue agregado a `LUA_FILES` en `tools/build_windows_exe.py`. | **BLOQUEANTE** | `[ ]` |
| 8 | Todos los sprites nuevos tienen su par `_n.png` y recargan en caliente con `[F5]`. | Importante | `[ ]` |
| 9 | Rendimiento >= 50 FPS en `--print-perf` en el equipo principal de demo. | Importante | `[ ]` |
| 10 | Repositorio limpio (`git status` sin archivos basura ni `.env` con claves reales) y commit de hito etiquetado (`fase-0X-ok`). | Importante | `[ ]` |

### Regla de Decisión de Hackathon (Timebox)
- **GO inmediato:** Los **7 criterios BLOQUEANTES** están en `[x]`. Cualquier detalle estético menor de los ítems 8–10 se anota en una lista corta de *"Pulido Fase 7"* y **se avanza ya** a la siguiente fase.
- **NO-GO (máximo 15 minutos de fix):** Falta 1 o más criterios **BLOQUEANTES**. Usa la Receta 2 o Receta 9 para resolver **solo** el bloqueante y vuelve a pasar el gate.

### Plantilla de Acta de Cierre de Fase (3 líneas para el chat del equipo)

```markdown
✅ GATE FASE [0X] — GO ([HH:MM])
- Entregable verificado: [ej. Combate HD-2D + ritual de flechas + 14 gags instantáneos]
- Evidencia: `screenshots/fase0X_*.png` aprobada en Astra | FPS: [60] | Offline smoke test: OK
- Diferido a Fase 7 (no bloqueante): [ej. afinar volumen de sfx_cry_wah en -2 dB] -> Pasamos a FASE [0X+1].
```
