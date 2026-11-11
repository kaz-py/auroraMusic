# Comandos de voz y letras con Whisper

Aurora entiende órdenes habladas **solo si empiezan por «Aurora»** y alinea las letras con el audio real. Todo se reconoce en tu equipo con [Whisper](https://github.com/openai/whisper) (modelo `ggml-small-q5_1`, vía [whisper.cpp](https://github.com/ggml-org/whisper.cpp), licencia MIT). Está apagado por defecto y solo existe en Windows y Linux (en Android no).

**Ajustes → Comandos de voz → Activar.** La primera vez descarga el modelo (180 MB, verificado con SHA-256) y abre el micrófono predeterminado.

## Qué se entiende

| Orden | Ejemplos |
|---|---|
| Pausar | «Aurora, pausa» · «Aurora, detén la música» · «Aurora, alto» |
| Continuar | «Aurora, continúa» · «Aurora, sigue» · «Aurora, reanuda» |
| Reproducir música | «Aurora, reproduce» · «Aurora, pon música» · «Aurora, toca música» |
| Siguiente | «Aurora, siguiente» · «Aurora, salta» · «Aurora, próxima canción» |
| Anterior | «Aurora, anterior» · «Aurora, vuelve atrás» |

También vale «Oye Aurora, …», «… por favor», o decir «Aurora» y, tras una pausa de menos de 4 s, la orden. Sin «Aurora» no hace nada: una orden suelta («pausa»), «Laura, pausa», «la aurora boreal…» o hablar de otra cosa se ignoran. «Reproduce música» con nada cargado empieza por la cola, la biblioteca o, si está vacía, el DJ personal. No entiende nombres de canciones o artistas.

## Cómo funciona

- El micrófono se lee en Rust (`rust/crates/aurora_voice`). Un detector de voz muy barato (energía cada 20 ms, con un umbral que sigue al ruido de fondo) corta el sonido en frases; **Whisper solo trabaja cuando alguien habla**, así que en reposo el coste es un medidor de nivel.
- Cada frase se **normaliza** antes de reconocerla (el nivel casi-pico se lleva a ~0,7; un soplido suelto no baja toda la voz), por eso no hace falta hablar pegado al micrófono: en las pruebas se entendieron órdenes con la señal 40 dB por debajo de lo normal.
- Whisper entrega texto libre; Aurora lo compara con las órdenes tolerando **una letra de error por palabra** («bon música» vale por «pon música») y exige que empiece por «aurora». La misma orden no se repite en 1,5 s. El ruido continuo (televisión, música) se descarta tras 6 s y sube el umbral para no volver a empezar.
- El modelo es **Whisper small**: en español comete aproximadamente la mitad de errores que `base` (Common Voice 10,3 % frente a 19,6 %; FLEURS 5,6 % frente a 9,9 %, [paper de Whisper](https://arxiv.org/pdf/2212.04356), tabla D.2) a cambio de ~3× más CPU por frase (≈1–1,5 s en un Ryzen 5 7600). Una pausa de hasta 0,9 s entre «Aurora» y la orden no parte la frase, y el silencio final se recorta a 0,24 s antes de entregarla.
- Las órdenes no tienen que ser frases exactas: «Aurora, pausa la canción», «Aurora, pon la siguiente», «Aurora, otra», «Aurora, para» o «A Aurora, continúa» valen. Se quitan las palabras de relleno y, si queda una sola palabra de acción, esa es la orden; dos acciones («pausa pausa») o palabras ajenas («pon pausa a todo») no cuentan.
- En **Ajustes** se ve el nivel del micrófono y «Escuché: …» con lo último que entendió, para saber por qué una orden no funcionó.
- Con una Jam activa, las órdenes pasan por la Jam y respetan tus permisos (igual que la API del Stream Deck).

## Letras alineadas con el audio

**Ajustes → Comandos de voz → Sincronizar las letras con el audio** (activado por defecto; actúa en cuanto el modelo está descargado).

1. Si la letra no tiene tiempos, se busca otra versión sincronizada con duración parecida. Si la sincronizada es más corta que la canción, se parte de esa diferencia como desfase.
2. Una vez por canción y en segundo plano se decodifica el audio (archivo o proxy local, sin tocar la reproducción) y Whisper lo transcribe con la hora de cada palabra (DTW). Esa transcripción, con sus errores y huecos, se alinea con el texto de la letra: cada línea con suficientes palabras en común queda anclada a un instante y las demás se reparten entre las ancladas.
3. Letra **sin tiempos**: cada línea recibe su hora (se salta la introducción y los pasajes instrumentales). Letra **sincronizada**: se conservan sus tiempos relativos y se corrige el desplazamiento (constante o interpolado entre anclas).
4. El resultado se guarda por canción (`lyrics/adjust.json`) y no se repite. Si no hay un resultado fiable, la letra queda como estaba.

Coste medido en un Ryzen 5 7600: unos 14 s de CPU para una canción completa (letra sin tiempos) y unos 4 s para los primeros 75–90 s (letra con tiempos). El modelo ocupa ~150 MB de memoria mientras analiza.

Con una canción real (*Berry Dreams*, inglés, con 30 s de introducción) la alineación situó el primer verso en el segundo 34 y reconoció 22 de 68 líneas; el modelo «tiny» solo 7. **No hay medición contra una letra sincronizada de referencia** (el banco de pruebas `tests/bench.rs` existe pero no pudimos descargar canciones con tiempos): la precisión real está sin medir.

## Diagnóstico (opcional)

**Ajustes → Comandos de voz → Guardar diagnóstico de voz** (apagado por defecto). Guarda en `<datos de Aurora>\voice\diagnostico` las últimas 40 frases que se entregaron a Whisper (`frase_<ms>.wav`, 16 kHz mono, ya normalizadas) y `diagnostico.jsonl` con, por cada una: texto que entendió Whisper, probabilidad de «no hay voz», decisión (`Command(...)`, `Wake` o `Ignored`), duración, pico y milisegundos de reconocimiento. Sirve para ver por qué una orden no se reconoce. Nada sale del equipo; al apagarlo el motor deja de guardar (los archivos existentes se pueden borrar a mano).

## Privacidad

El audio se reconoce en tu equipo: no se guarda ni se envía. El micrófono solo se abre mientras el interruptor esté activado. El modelo es el único archivo que se descarga.

## Límites conocidos

- **Procesadores con AVX2 y FMA** (cualquiera desde 2013): ggml se compila con esas instrucciones y Aurora lo comprueba antes de cargar el modelo; en otros no se activa.
- Si Aurora suena por altavoces, el micrófono la oye: con auriculares va mucho mejor. Una canción que dijera «Aurora, pausa» la pausaría. **No hay cancelación de eco todavía.** Se probó en simulación (música + eco retrasado con reverberación, AEC3 de WebRTC vía la crate `aec3`, referencia = lo que Aurora reproduce): la música baja ~25 dB, pero el detector de voz por energía no sabe separar la voz del residuo (~−45 dB que sigue ahí), así que integrarlo exige además una toma de la salida del reproductor y un detector de voz neuronal (Silero). No está integrado.
- Windows debe permitir el micrófono a las apps de escritorio (Configuración → Privacidad → Micrófono). Si no entrega sonido, Ajustes lo avisa a los 8 s.
- Órdenes solo en español. Las letras se alinean en el idioma que se deduce del texto (o que detecta Whisper).
- Whisper puede inventar texto con ruido: por eso solo se obedece lo que empieza por «Aurora» y encaja con una orden.

## Pruebas y compilación

El motor de voz compila whisper.cpp dentro de la biblioteca de Rust: hace falta **CMake** y **LLVM (libclang)** además de Rust (en Windows, `winget install LLVM.LLVM`, `LIBCLANG_PATH` apuntando a su `bin`, y CMake en el `PATH`; sirve el que trae Visual Studio: `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin`). `.cargo/config.toml` fija los flags de ggml (AVX2/FMA; sin ellos MSVC compila sin AVX2 y sin optimizar y la inferencia va ~13× más lenta).

```bash
cargo test -p aurora_voice --release            # órdenes, VAD y alineación (sin modelo)
# Reconocimiento real con voz sintética (dos voces) y el modelo:
AURORA_WHISPER_MODEL=<ggml-base-q5_1.bin> cargo test -p aurora_voice --release
# Banco con canciones reales (X.wav a 16 kHz mono + X.json con la letra sincronizada):
AURORA_WHISPER_MODEL=... AURORA_BENCH_DIR=<carpeta> cargo test -p aurora_voice --release --test bench -- --ignored --nocapture
```

Los audios de `rust/crates/aurora_voice/tests/fixtures/` son voz sintética (Edge TTS, `es-MX-DaliaNeural` y `es-ES-AlvaroNeural`).
