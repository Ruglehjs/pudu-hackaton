# Resultados de la Fase 7

**Dictamen de salida · BLOQUEADO.** La build candidata ganó un combate offline desde el `.love` y desde el `.exe` recién extraído. La aprobación de escenario queda pendiente por el inventario de arte y audio, el Panel Director, el pipeline Deferred/GI y las caídas de FPS observadas.

Se verificó LÖVE 11.5 en Windows con una Intel UHD Graphics 620. La base fue `b6cdc69`, el HEAD de `main` en GitHub. La revisión visual se realizó sobre las capturas de esta ejecución.

## Evidencia y reproducción

```powershell
python -m pip install -r requirements.txt
python -m unittest discover -s tests
python tests/smoke_game.py
python tools/qa_demo.py --live
```

El [manifiesto de QA](../../screenshots/qa_final/manifest.json) contiene los argumentos, las métricas y la salida de cada corrida, el inventario faltante y el resultado individual del fuzzing. `--live` añade tres solicitudes al proveedor configurado. Las capturas ordinarias usan `--qa-no-save` para aislar el álbum y las personalizaciones de escenario. La captura del álbum poblado usa una partida sintética en una carpeta temporal.

- **Módulos y build.** Se verificaron los `require` empaquetados, la sintaxis, la firma `MZ` y la arquitectura x86-64 del ejecutable y de las siete DLL, además de los CRC del `.love`, el `.exe` fusionado y el ZIP. El pipeline `lighting_pipeline.lua` y el Panel Director están ausentes de la revisión base.
- **Inventario.** 22 de 125 archivos de arte, fuente y audio requeridos están empaquetados. Se verificaron 11 pares de PNG y mapas de normales con dimensiones coincidentes, incluida la hoja del Pudú de 6×8. Faltan 103 archivos, entre ellos la fuente PT Sans, el audio activo, el sombrero final, seis rivales, los tiles y los gags.
- **Capturas.** Las 15 corridas principales terminaron con código 0, sin errores del juego ni advertencias GLSL y con PNG de 1280×720. Se obtuvieron 14 de las 15 escenas esperadas. La captura 13 muestra el estado real al pasar `--open-director` y evidencia que el panel falta. Se incluyen cuatro capturas complementarias.
- **Rendimiento.** La pasada a 1280×720 registró 49 FPS en Bosque, 52 en Atacama, 40 en Costa, 54 en Chiloé, 44 durante la entrada a batalla y 60 en la escena nocturna. Una repetición de 4,2 s dio 55 FPS en Costa y 60 FPS en el atardecer. Con `--disable-bloom`, las mismas escenas dieron 59 y 60 FPS. Se observaron caídas por debajo del mínimo de 45 FPS para una GPU integrada.
- **Fuzzing.** 16/16 grupos de casos en Lua y 16/16 por HTTP mock, con 22 variantes en cada modo y 34 campos exactos por respuesta. Los tres casos reales de Gemini pasaron tras corregir el tratamiento de las debilidades conocidas. La batería usa el mínimo vigente de 96 de daño base del Electro-Charco. El juego registró 127 con el ritual completo.
- **Smoke offline.** `lavadora` venció a la Pila de Ropa en un turno con 116 de daño, bandera blanca y registro en el álbum en memoria. El puerto del puente se reservó sin servidor y ambos formatos ejecutaron el juez Lua. La regresión adicional desconectó el puente a mitad de un combate y completó el combo en Lua. Pasaron las 20 pruebas de Python y las dos suites de Lua.

## Build candidata de Windows x64

- `dist/PuduFantasy.love` · 440 610 bytes.
- `dist/PuduFantasy-Windows/PuduFantasy.exe` · 827 682 bytes.
- `dist/PuduFantasy-Windows-x64.zip` · 4 863 958 bytes.

El ZIP incluye el ejecutable, las siete DLL, `Jugar_con_IA.bat`, `LEEME_WINDOWS.txt` y las carpetas `assets/custom/` y `screenshots/`. El lanzador de IA usa Python cuando está disponible. El `.exe` abre directamente el juego.

## Revisión visual de 12 puntos

1. **PASS · Carriles.** En `07` a `10`, la bandeja, los globos, los estados y los rótulos de daño conservan espacio propio.
2. **WARN · Glifos.** En `07`, `12` y `14b` se leen el texto en español y los iconos sin caracteres rotos. Queda pendiente repetir con PT Sans y con el Panel Director integrado.
3. **PASS · Flechas.** En `07` se distinguen las cuatro direcciones, con contorno limpio.
4. **WARN · Bloom.** En `06`, `09` y `10` se conserva la legibilidad del HUD y del sombrero. En los impactos, los destellos aclaran parte de las caras provisionales. Repetir con el arte definitivo de los rivales.
5. **PASS · Anticipación.** En `07`, el globo apunta al rival, permanece dentro de pantalla y deja libre la bandeja de flechas.
6. **PASS · Daño crítico.** En `08`, `09` y `10` se lee el daño a la derecha del rival sin tocar el banner.
7. **PASS · Finales.** En `15` y `15b` se ven la rendición y el confeti de la Pila de Ropa. La vista `08b` comprueba las lágrimas, el charco y la bandera con una reacción forzada.
8. **PASS · Álbum.** Nueve tarjetas completas en `14` vacío y `14b` con tres victorias sintéticas. Los textos con `ñ` y tildes se ajustan a las tarjetas.
9. **PASS · HUD inferior.** En `06` y `08` se mantiene la franja de 78 px y el espacio reservado al prompt.
10. **PASS · Sombrero.** El sombrero procedural se mantiene anclado al caminar y al combatir en las vistas revisadas.
11. **FAIL · Iluminación avanzada.** En `11` y `12`, los personajes se distinguen y las luces responden a los presets. La revisión ejecuta `lit` y `post` con `deferred=false` y `gi=false`, por lo que faltan la evidencia y el pipeline de SDF/GI exigidos por la fase.
12. **PASS · Exploración y transición.** En `01` a `05b`, la ruta diagonal, los cuatro biomas, la alerta y el minimapa se distinguen. El cuarto bioma de campaña es Chiloé.

## Pendientes del gate

1. Incorporar el inventario de arte, fuente y audio de la demo. Probar el balance en el equipo de presentación con `F8` disponible para silenciar.
2. Integrar el Panel Director y repetir la escena 13 y su revisión de texto.
3. Integrar el pipeline Deferred/GI previsto y repetir las escenas de iluminación y combos.
4. Repetir el gate de rendimiento con la build completa, el equipo de presentación y el proyector conectados.
5. Ensayar el guion con el equipo, probar la recuperación offline y respaldar el álbum que se usará en el escenario.

## Guion de 180 segundos

Prepara el ZIP extraído, confirma el proveedor de IA con `/health` y abre `Jugar_con_IA.bat --mode=explore --encounter=1`. El Pudú quedará cerca de la Pila de Ropa. Conserva un acceso directo a `PuduFantasy.exe --mock` para el plan offline.

- **0:00–0:25 · Atacama.** Camina hacia arriba y a la derecha. «Este es Pudú Fantasy, un RPG donde la arena responde a tus ideas. En vez de elegir un ataque, escribes qué quieres invocar».
- **0:25–0:45 · Encuentro.** Acércate a la Pila de Ropa para mostrar la alerta y la entrada a la arena. Usa `Tab` si el botón de combate ya aparece. «Cada rival tiene una debilidad que puedes descubrir jugando con lo que hay en escena».
- **0:45–1:20 · Primer crítico.** Escribe `lavadora`, pulsa `Enter` y completa las flechas. «Una pila de ropa contra una lavadora. El ritual carga el golpe mientras se resuelve la invocación». Deja que aparezca la bandera blanca.
- **1:20–1:55 · Combo.** Pulsa `Ctrl+5` para saltar al Pantano Traicionero. Conjura `charco` y luego `rayo eléctrico`, completando ambos rituales. «El primer turno deja MOJADO. El segundo usa ese estado para desatar el Electro-Charco».
- **1:55–2:35 · Idea del jurado.** Pulsa `Ctrl+7` para entrar al Gato Guatón y pide un objeto absurdo. Si hace falta, escribe `ornitorrinco dj con lentes láser`. Completa el ritual mientras llega el sprite del proveedor. «El juego recibe la idea y la convierte en un ataque dentro de la arena».
- **2:35–3:00 · Álbum y cierre.** Pulsa `J` o `Ctrl+J` si el campo de prompt está activo. Muestra las victorias guardadas. «La build es portable y el juego puede resolver los combates con Lua si se corta el puente».

Si falla el proveedor durante el ensayo, sigue con la build iniciada con `--mock`. Los tres momentos offline son `lavadora` contra la Pila de Ropa, `charco` seguido de `rayo eléctrico` en el Pantano Traicionero y `pepino verde` contra el Gato Guatón. El álbum se abre con `J` y la iluminación se puede recorrer con `F7`.
