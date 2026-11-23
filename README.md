# Pudú Fantasy

RPG de combate por turnos ambientado en cuatro biomas chilenos. Escribe una invocación, observa qué le pasa al rival y aprovecha el estado que queda en la arena en el turno siguiente.

## Jugar en Windows

Abre **Jugar_Windows.bat**. El lanzador busca LÖVE 11.5 en `tools/love-win64/` o en el PATH. La copia local de la demo incluye el motor.

- Camina con WASD o las flechas. Acércate a un rival o pulsa Tab para combatir.
- En la arena, escribe una idea y pulsa Enter. Puedes pegar con Ctrl+V y corregir con Retroceso.
- Esc o Tab te devuelve al mapa. Los rivales vencidos quedan marcados durante la partida.
- F8 alterna el sonido y F12 guarda una captura. F5 recarga el arte.

Para entrar directamente en una pelea o reproducir un combo desde PowerShell:

```powershell
.\Jugar_Windows.bat --mode=battle --encounter=1
.\Jugar_Windows.bat --mock --demo-combo=combo_electro
```

Los nueve rivales admiten invocaciones libres. El juez local reconoce debilidades, curas, autogoles, ocho estados y seis combos. El modo `--mock` evalúa en Lua. En macOS y Linux puedes usar `./run.sh` con LÖVE 11.5.

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
