# Plugin de Stream Deck para Aurora

Carpeta independiente del resto del proyecto: el plugin (`com.aurora.music.sdPlugin`) no comparte código con la app Flutter; solo habla con su API local (ver [`docs/stream_deck.md`](../docs/stream_deck.md)). El lado de Aurora vive en `lib/remote/`.

## Teclas

| Tecla | Qué hace |
|---|---|
| Reproducir / pausar | Alterna; el icono sigue el estado real de Aurora |
| Siguiente canción | Pasa a la siguiente |
| Canción anterior | Vuelve a la anterior |
| Iniciar Jam | Abre una Jam. En la tecla se elige dónde: automático, en línea o red local |

Cada tecla confirma con la marca verde o muestra la alerta si falla (Aurora cerrada, token incorrecto, permisos de la Jam…). El motivo queda en el registro del Stream Deck.

## Instalar

1. En Aurora: **Ajustes → Control remoto (Stream Deck) → Activar la API local**.
2. Instala el plugin: doble clic en `com.aurora.music.streamDeckPlugin` (se genera con `npm run pack`), o copia `com.aurora.music.sdPlugin` a `%APPDATA%\Elgato\StreamDeck\Plugins\`.
3. Arrastra las teclas de la categoría **Aurora** a tu Stream Deck.

## Configurarlo desde el Stream Deck

Al seleccionar cualquier tecla de Aurora, el panel de propiedades muestra **Conexión con Aurora**, común a todas las teclas:

- **Automática (recomendado)**: no hay nada que escribir. Aurora publica su URL y token en `%APPDATA%\com.aurora\Aurora\remote_control.json` mientras la API está activa y el plugin lo lee en cada pulsación; si regeneras el token, sigue funcionando.
- **Manual**: escribe la URL (solo `http://127.0.0.1…`; el plugin rechaza cualquier otra para que el token no salga del equipo) y el token que copiaste de Ajustes.
- **Probar conexión** indica si funciona, o por qué no, y qué canción suena.

## Desarrollo

```bash
cd streamdeck
npm install        # solo para las pruebas (ws); el plugin no tiene dependencias
npm test           # 15 pruebas: cliente WebSocket, teclas, conexión, manifiesto
npm run pack       # dist/com.aurora.music.streamDeckPlugin
```

El plugin usa Node 20 (el que incluye el Stream Deck 6.4+) sin paquetes: el cliente WebSocket es propio (`lib/websocket.js`, RFC 6455) y las pruebas lo contrastan con la librería `ws`.

**Sin verificar:** no hay un Stream Deck instalado en la máquina de desarrollo. El protocolo se probó contra un Stream Deck simulado, la API real de Aurora (servidor Dart) y el panel de propiedades en Chromium; falta instalarlo en el programa de Elgato y pulsar las teclas de verdad.
