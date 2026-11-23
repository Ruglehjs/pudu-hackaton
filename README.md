# Pudú Fantasy

RPG de combate por turnos ambientado en cuatro biomas chilenos. Escribe una invocación, observa qué le pasa al rival y aprovecha el estado que queda en la arena en el turno siguiente.

## Jugar en Windows

Abre **Jugar_Windows.bat**. El lanzador busca LÖVE 11.5 en `tools/love-win64/` o en el PATH. La copia local de la demo incluye el motor.

Si tienes el ZIP portátil, extrae la carpeta completa y ejecuta **PuduFantasy.exe**.

- Camina con WASD o las flechas. Acércate al siguiente rival o pulsa Tab cuando aparezca el botón de combate.
- En la arena, escribe una idea y pulsa Enter. Puedes pegar con Ctrl+V y corregir con Retroceso.
- Cuando aparezca el ritual, sigue las flechas con el teclado o con WASD para potenciar el golpe.
- Esc o Tab te devuelve al mapa. Los rivales vencidos quedan marcados durante la partida.
- F8 alterna el sonido y F12 guarda una captura. F5 recarga el arte.
- En combate, F7 cambia la iluminación y Ctrl+1 a Ctrl+9 salta a un rival para pruebas.

Para entrar directamente en una pelea o reproducir un combo desde PowerShell:

```powershell
.\Jugar_Windows.bat --mock --mode=battle --encounter=1
.\Jugar_Windows.bat --mock --demo-combo=combo_electro
.\Jugar_Windows.bat --mock --demo-finale=crying
```

La aventura comienza en el Desierto de Atacama con la Pila de Ropa. Sigue por Costa con la Gaviota Mafiosa y por Bosque con el Puma Dramático. El Caleuche espera al final en Chiloé. Cada victoria abre el camino al siguiente encuentro.

Los cuatro rivales de la aventura admiten invocaciones libres. El juez local reconoce debilidades, curas, autogoles, ocho estados y seis combos. El modo `--mock` evalúa en Lua. En macOS y Linux puedes usar `./run.sh` con LÖVE 11.5.

Para iniciar un combate directamente, usa `--mode=battle --encounter=1` y cambia el número del 1 al 4 según el orden de la aventura. Los números 5 al 9 abren combates de QA.

Para probar un reemplazo local del arte del mapa, coloca el PNG y su mapa de normales `_n.png` en `assets/custom/` con el nombre del original y pulsa F5. Los suelos y sprites originales están en el [repositorio Flora y Fauna Chilena](https://github.com/Ruglehjs/flora-y-fauna-chilena-sprites/tree/468faea58bc6cc07307a0c797185ed7785978051).

## Puente de IA opcional

Con Python 3.10 o superior, el lanzador puede iniciar el puente en el puerto local 18425. Para usar los modelos de Google, instala las dependencias con `python -m pip install -r requirements.txt`. Copia `.env.example` a `.env` y configura `GEMINI_API_KEY` o las credenciales ADC de Vertex AI con `GOOGLE_CLOUD_PROJECT`. El puente también puede iniciarse con `python ai_bridge.py`.

Los gags conocidos usan arte local y admiten PNG de reemplazo en `assets/custom/`. La generación de sprites nuevos requiere un proveedor de imágenes habilitado. Si se desconecta el puente, el combate continúa con el juez Lua y el arte provisional.

## Verificar y empaquetar

```powershell
python -m unittest discover -s tests
python tests/smoke_game.py
python tools/build_windows_exe.py
```

El empaquetador usa el motor en `tools/love-win64/` y produce el ejecutable portable en `dist/PuduFantasy-Windows/` y su ZIP. Mantén las DLL junto al ejecutable.

La prueba de integración abre una partida, desconecta el puente entre turnos y verifica que el combo termina en Lua. Si tienes LuaJIT, puedes ejecutar también `luajit tests/test_offline_lua.lua`.
