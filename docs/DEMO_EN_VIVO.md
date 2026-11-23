# Pudú Fantasy · Guion para el demo

**Ruta completa · 4 a 6 minutos.** Parte en Atacama, gana los cuatro combates en orden y deja en pantalla «¡Aventura completada!». Desde la raíz del proyecto, abre `./run.sh --mock` para ensayar con el juez local. Pega los prompts con ⌘+V en Mac o Ctrl+V en Windows y confirma con Enter.

> «Este pudú cruza Chile a punta de malas ideas. Hasta el charco que deja una invocación nos puede servir en el turno siguiente.»

Deja correr la llegada a Atacama. Si pasas cerca de Bodoque, espera su «¡La ruta de la caca!» antes de seguir. Acércate a Fardo y entra al combate con Tab cuando aparezca el botón. Después de cada victoria, vuelve al mapa con Enter y dale un segundo al mensaje del bioma antes de seguir caminando.

## 1 · Atacama con Fardo

| Escribe | Qué mostrar y qué decir |
|---|---|
| `modo dios` | El árbitro pide una invocación. «Ya, descubrimos que hacer trampa no cuenta como magia.» Sigues en el mismo turno. |
| `calcetín` | Autogol. Fardo se ríe y contraataca. «Le traje un calcetín a una montaña de ropa. Le acabo de hacer un despacho.» |
| `curita` | Opcional. La barra del Pudú sube antes del contraataque. «El pudú también puede improvisar primeros auxilios.» |
| `ornitorrinco DJ con poncho y tornamesa de cobre` | La invocación hace daño normal. Deja que termine el contraataque y lee el globo de Fardo sobre la ropa recién lavada. Esta es la segunda jugada válida sin crítico. |
| `burbujas de jabón` | El crítico aprovecha la pista. «Era día de lavado y yo traje un DJ.» Espera la despedida de Fardo antes de volver al camino. |

En el ritual del ornitorrinco, pulsa una flecha equivocada y luego la correcta. La secuencia espera y puedes completar el hechizo. Antes de la última flecha, prueba un círculo con el mouse o sigue un objetivo que se deslice para subir el poder.

## 2 · Valparaíso con La Mancha

1. `charco` — Completa el ritual. Deja que La Mancha contraataque y apunta al estado **MOJADO** cuando vuelva tu turno. «El charco quedó ahí. ¿Qué le tiramos ahora?»
2. `rayo eléctrico` — Deja que se vea la anticipación del rival, termina las flechas y haz una pausa para el **Electro-Charco**. «Hasta el charco baila cueca.»

## 3 · Bosque valdiviano con Brasa

1. `nube de lluvia` — La nube aparece sobre Brasa. «Al jefe del fogón le cae el clima valdiviano.» Es buen momento para mostrar el sprite local y la lluvia.
2. `extintor` — Úsalo si Brasa sigue en pie. Al volver al mapa, deja que se lea el mensaje de los árboles recuperados.

## 4 · Chiloé con Témpano

1. `secador de pelo` — Completa las cuatro flechas y muestra el estado **CALIENTE**. «Primero le hacemos la permanente.»
2. `charco con flotador de flamenco` — Completa el ritual. El calor del turno anterior convierte el agua en el **Sauna Vapor**. «En Valpo el agua nos dio electricidad. Acá abrimos unas termas.» Si queda HP, remata con `estufa`.

Deja la victoria en pantalla. «Cuatro biomas salvados. El ornitorrinco se queda hasta que le paguen el evento.»

## Si queda poco tiempo

- **Dos minutos.** Abre `./run.sh --mock --mode=battle --encounter=1`. Haz Fardo sin la curita. En la pantalla de victoria, pulsa Ctrl+2 para saltar a La Mancha y cierra con Electro-Charco.
- **Sprite en vivo.** Abre `./run.sh` con el puente de IA de texto e imagen configurado. El ornitorrinco es el candidato para ilustrar lo que la gente invente. Si quieren proponer un detalle, cambia el poncho por lo que griten y conserva «ornitorrinco DJ». La valoración y el arte pueden variar con el proveedor. Si la generación tarda, aprovecha las flechas y los objetivos extra que aparezcan durante la espera.
- **Mostrar un combo de inmediato.** `./run.sh --mock --demo-combo=combo_electro` juega los dos turnos automáticamente.
- **Un detalle visual.** Pulsa F7 en el muelle para cambiar la iluminación y deja que el Pudú baile un par de compases antes de escribir.
