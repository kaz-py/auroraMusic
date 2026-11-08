# Control remoto (Stream Deck)

Aurora puede abrir una API HTTP **solo en este equipo** para que un Stream Deck (o un script) pause, salte de canción e inicie una Jam. Está apagada por defecto y solo existe en Windows y Linux.

## Activarla

1. **Ajustes → Control remoto (Stream Deck) → Activar la API local**.
2. Pulsa **Copiar URL** y **Copiar token**. La URL por defecto es `http://127.0.0.1:47890/v1`.
3. **Regenerar token** invalida el anterior: lo que lo use deja de funcionar.

El puerto se guarda en la preferencia `remoteControlPort` (por defecto 47890). Si está ocupado, Ajustes lo avisa.

## Rutas

Todas aceptan `GET` o `POST` y devuelven JSON (`{"ok": true, …}` o `{"ok": false, "error": "…"}`).

| Ruta | Qué hace |
|---|---|
| `/v1/status` | Estado: `playing`, `buffering`, `track`, `positionMs`, `durationMs`, `queueLength`, `jam` |
| `/v1/play`, `/v1/pause`, `/v1/toggle` | Reproducir, pausar, alternar |
| `/v1/next`, `/v1/previous` | Siguiente, anterior |
| `/v1/jam/start` | Inicia una Jam. `mode`: `auto` (en línea si hay servidor; si no, red local), `online` o `lan` |

`jam/start` devuelve `alreadyActive: true` si ya había una Jam, y el código de invitación en `jam.code` cuando es en línea. Con una Jam activa, pausa y siguiente pasan por la Jam y respetan tus permisos (un invitado sin permiso recibe `409`); `previous` no existe en una Jam.

## Token

Se envía de cualquiera de estas formas:

- `Authorization: Bearer <token>`
- `X-Aurora-Token: <token>`
- `?token=<token>` (para clientes que solo permiten una URL)

## Con un Stream Deck

Usa un plugin que haga peticiones HTTP en segundo plano (por ejemplo *API Ninja*), con una acción por botón:

- Método `POST`, URL `http://127.0.0.1:47890/v1/toggle` (o `next`, `jam/start`…).
- Cabecera `Authorization: Bearer <token>`.

Probar desde una terminal:

```bash
curl -X POST -H "Authorization: Bearer <token>" http://127.0.0.1:47890/v1/next
curl -X POST -H "Authorization: Bearer <token>" -d '{"mode":"lan"}' http://127.0.0.1:47890/v1/jam/start
```

## Seguridad

- Escucha solo en `127.0.0.1`; no es accesible desde la red.
- Todas las rutas exigen el token (128 bits, comparación en tiempo constante).
- Se rechazan peticiones con cabecera `Origin` (cualquier página web) y con un `Host` que no sea el propio, y no se envían cabeceras CORS: un navegador no puede usarla aunque adivine el puerto.
- Cuerpos de hasta 4 KiB. Los errores inesperados no revelan detalles internos.
- Cualquier programa de tu equipo que conozca el token puede controlar la reproducción; trátalo como una contraseña de ese alcance.
