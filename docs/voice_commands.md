# Comandos de voz

Aurora puede obedecer órdenes habladas, **solo si empiezan por «Aurora»**. Está apagada por defecto y solo existe en Windows y Linux (en Android no).

**Ajustes → Comandos de voz → Activar.** La primera vez descarga un modelo de voz en español (40 MB, verificado con SHA-256) y abre el micrófono predeterminado.

## Qué se entiende

| Orden | Ejemplos |
|---|---|
| Pausar | «Aurora, pausa» · «Aurora, detén la música» · «Aurora, alto» |
| Continuar | «Aurora, continúa» · «Aurora, sigue» · «Aurora, reanuda» |
| Reproducir música | «Aurora, reproduce» · «Aurora, pon música» · «Aurora, toca música» |
| Siguiente | «Aurora, siguiente» · «Aurora, salta» · «Aurora, próxima canción» |
| Anterior | «Aurora, anterior» · «Aurora, vuelve atrás» |

También vale decir «Aurora…» y, tras una pausa de menos de 4 s, la orden. Sin «Aurora» no hace nada: una orden suelta («pausa»), «Laura, pausa» o hablar de otra cosa se ignoran. «Reproduce música» con nada cargado empieza por la cola, la biblioteca o, si está vacía, el DJ personal.

No entiende nombres de canciones o artistas: el reconocedor está cerrado a estas frases a propósito (es lo que lo hace fiable y ligero).

## Cómo funciona

- El micrófono se lee en Rust (`rust/crates/aurora_voice`) y se reconoce con [Vosk](https://alphacephei.com/vosk/) (modelo `vosk-model-small-es-0.42`, Apache 2.0) restringido a una gramática con solo estas frases más `[unk]`.
- Una orden se acepta si **todas** sus palabras tienen confianza ≥ 0,6, no hay palabras desconocidas y empieza por «aurora»; la misma orden no se repite en 1,5 s.
- `libvosk` se carga al activar la función (no se enlaza): si faltara, solo esta función falla, con un mensaje. En Windows viene en `tools/vosk/` junto a la app (lo instala `scripts/setup_tools.ps1` con versión y SHA-256 fijados). En Linux se busca `lib/libvosk.so` junto a la app o la del sistema.
- Con una Jam activa, las órdenes pasan por la Jam y respetan tus permisos (igual que la API del Stream Deck).

## Letras sincronizadas con el audio

Con el mismo modelo, Aurora corrige sola las letras que van desfasadas (por ejemplo, un vídeo con una introducción que la versión de estudio no tiene). **Ajustes → Comandos de voz → Sincronizar las letras con el audio** (activado por defecto; actúa en cuanto el modelo está descargado, que se hace al activar cualquiera de las dos funciones).

1. Al elegir la letra, si hay varias versiones, se prefiere la de duración más cercana. Si la sincronizada es más corta, se parte de esa diferencia como desfase.
2. Después, una vez por canción y en segundo plano, se decodifican los primeros 100 s del audio (archivo o proxy local, sin tocar la reproducción) y se reconocen con una gramática hecha solo con las primeras líneas de la letra. De cada línea reconocida sale un desfase (momento en el audio − tiempo de la letra) y vale la mediana de los que coinciden (al menos dos, o una larga y muy segura). Un desfase menor de 0,4 s se ignora.
3. Si no hay resultado fiable, la letra queda como estaba (y no se reintenta con esa canción).

Los botones − / + de la letra siguen mandando: un ajuste hecho a mano nunca se pisa, y «Letra: sin ajuste» elegido por ti gana al automático.

Límites: solo letras en español (las palabras que el modelo no conoce se descartan) y canto reconocible sobre el acompañamiento; en pruebas con voz sintética sobre ruido fuerte acertó o no dio resultado, pero no se ha medido con canciones reales.

## Privacidad

El audio se reconoce en tu equipo: no se guarda ni se envía. El micrófono solo se abre mientras el interruptor esté activado, y la barra de nivel de Ajustes muestra si llega sonido.

## Límites conocidos

- Si Aurora suena por altavoces, el micrófono la oye: con auriculares funciona mejor. Una canción que dijera «Aurora, pausa» la pausaría.
- Con ruido fuerte o varias personas hablando puede fallar.
- Windows debe permitir el micrófono a las apps de escritorio (Configuración → Privacidad → Micrófono). Si no entrega sonido, Ajustes lo avisa a los 8 s.
- La ruta de datos de tu cuenta de Windows debe poder escribirse en la página de códigos ANSI (acentos y ñ sí; alfabetos como el cirílico, no).
- Solo español. Otro idioma exige otro modelo.

## Pruebas

```bash
cargo test -p aurora_voice --release            # lógica de órdenes e instalación del modelo
# Reconocimiento real (voz sintética, dos voces) con libvosk y el modelo:
AURORA_VOSK_LIB=<libvosk.dll> AURORA_VOSK_MODEL=<carpeta del modelo> cargo test -p aurora_voice --release
# Micrófono real:
... cargo test -p aurora_voice --release --test device -- --ignored --nocapture
```
Los audios de `rust/crates/aurora_voice/tests/fixtures/` son voz sintética (Edge TTS, `es-MX-DaliaNeural` y `es-ES-AlvaroNeural`).
