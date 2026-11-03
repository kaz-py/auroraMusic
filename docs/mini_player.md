# Mini reproductor (1.5.0)

Base compartida por los cuatro temas (Atelier, Modern, Brasa, Slush). Código en
`lib/ui/mini_player/`; pruebas en `test/mini_player/`.

## Ajuste

`AppController.blurredCoverMode` (`bool`, clave `blurredCoverMode`, apagado por
defecto) y `setBlurredCoverMode(bool)` (guarda y avisa). Interruptor «Fondo
difuminado de la portada» en Ajustes > Apariencia (sección «Fondo de portada»).
Igual para todos los temas.

## Piezas

| Archivo | Qué es |
| --- | --- |
| `cover_tone.dart` | `CoverTone`: velo + texto que cumplen contraste ≥ 4,8 (requisito 4,5) sobre **todas** las muestras de la portada. Cálculo puro. |
| `cover_backdrop_source.dart` | `CoverBackdropSource` / `CoverBackdropCache` (LRU 16): decodifica a 96 px, difumina **una vez** (sigma 8 a esa resolución ≈ 28 px lógicos en 340 px), muestrea una rejilla 8×8. Sin portada o con fallo devuelve `null`. |
| `blurred_cover_backdrop.dart` | `BlurredCoverBackdrop` y `BlurredCoverTheme`. |
| `mini_player_model.dart` | `MiniPlayerState` (vista derivada del controlador y la Jam) y `MiniPlayerActions`. |
| `mini_player_gestures.dart` | `MiniPlayerGestures`: toque, arrastre arriba, deslizar a los lados. |
| `mini_player_theme.dart` | `MiniPlayerBuilder` y `MiniPlayerTheme`. |
| `mini_player_host.dart` | `MiniPlayerHost` y registro `miniPlayerThemes`. |
| `atelier_/modern_/brasa_mini_player.dart`, `slush_mini_player_v2.dart` | Un tema cada uno (fase 2). Hoy delegan en la barra de siempre (`legacy: true`). |
| `mini_player_legacy.dart` | Puente temporal a `StudioTransport`, `SlushPlayerBar` y `SlushMiniPlayer`. Se borra cuando ningún tema sea `legacy`. |

## `BlurredCoverBackdrop`

```dart
BlurredCoverBackdrop(
  track: state.track,            // null o sin portada: solo se pinta child
  radius: BorderRadius.circular(16),
  child: Builder(builder: (context) {
    final tone = BlurredCoverTheme.of(context);   // foreground, secondary, scrim
    return Text(artist, style: TextStyle(color: tone.foreground));
  }),
)
```

- Velo claro u oscuro según la portada, con el alfa mínimo que garantiza el
  contraste de `foreground` y `secondary` sobre cualquier píxel muestreado.
  Sin portada, `BlurredCoverTheme.of` devuelve los colores del tema y
  `BlurredCoverTheme.isActive(context)` es falso.
- `DefaultTextStyle` e `IconTheme` del hijo ya llevan `foreground`.
- Cruce de portadas en 350 ms (`kCoverCrossfade`); la antigua se queda hasta que
  carga la nueva. Movimiento reducido (`MediaQuery.disableAnimationsOf`):
  instantáneo. Al cruzar portadas de distinto tono el color del texto cambia a
  mitad del cruce y el contraste baja a ~4 durante < 350 ms; en reposo es ≥ 4,8.
- `matchTheme: true` (cabecera del reproductor, `VinylPlayer`): el velo es el
  fondo del tema y el texto el del tema; `fadeBottom` funde el borde inferior.
- Pruebas: `blurred_cover_backdrop_test.dart` (blanca, negra, gris, saturadas,
  ajedrez, aleatoria).

## `MiniPlayerHost`

```dart
MiniPlayerHost(
  controller: c, section: _section, rail: rail,
  placement: MiniPlayerPlacement.body,   // o bottomBar (SlushBottomBar.mini)
  jam: _jam, onOpenPlayer: () => _navigate(4), onTogglePlay: () => _togglePlay(c),
  legacy: MiniPlayerLegacyBars(...),
)
```

El shell monta dos hosts (cuerpo y barra inferior de Slush); solo dibuja el que
corresponde a `MiniPlayerHost.placementFor`. Va en flujo, así que el shell
reserva su altura sin medirla. `MiniPlayerHost.heightFor(context, wide:)` es la
altura mínima (56 móvil, 64 con carril, hasta ×1,5 con el texto).

Un tema nuevo se registra en `miniPlayerThemes` con
`MiniPlayerTheme(build: ...)` (sin `legacy`):

```dart
typedef MiniPlayerBuilder = Widget Function(
  BuildContext context, MiniPlayerState state, MiniPlayerActions actions,
  {required bool blurred, required bool wide});
```

- `wide`: diseño con carril (≥ 600 px); el resto, móvil sobre la navegación.
- `blurred`: ajuste activo **y** la pista tiene portada.
- El host ya aplica: oculto sin pista, en la sección 4 y en la página oficial de
  YouTube Music; `MiniPlayerGestures` y la altura mínima. El tema no repite
  gestos ni visibilidad: dibuja y cablea play, favorito y siguiente.
- Con `legacy: true` el host conserva las reglas de antes (Atelier/Modern/Brasa
  siempre visibles también sin pista; Slush oculto en la sección 4; con Jam,
  `StudioTransport` en el cuerpo) y no envuelve en gestos.

Migración de un tema (fase 2): reemplazar el cuerpo de `_build` en su archivo,
quitar `legacy: true`.

## Modelo y acciones

`MiniPlayerState.fromController(c, jam:)`: `track` (`nowTrack`), `isPlaying`,
`progress` 0..1, `buffering`, `hasError`, `liked`, `hasNext`, `hasPrevious`,
`jamActive`, `canTogglePlay`, `jamHostName`. Con Jam: sin «anterior», siguiente
solo con permiso o voto.

`MiniPlayerActions.forController(c, jam:, openPlayer:, togglePlay:)` usa los
métodos del controlador y de la Jam; no hay lógica propia.

## Gestos

Umbrales (iguales con movimiento reducido): abrir 40 px o 600 px/s hacia
arriba; salto de pista 64 px o 700 px/s. Los umbrales cuentan desde que el dedo
supera el umbral de arrastre de Flutter. La barra sigue al dedo con resistencia
(solo `transform`) y vuelve con un muelle que hereda la velocidad. Un único
nodo semántico con acciones (abrir, siguiente, anterior); los botones del hijo
conservan el suyo.

## Brasa (`brasa_mini_player.dart`)

Barra acoplada al borde inferior (esquinas superiores de 6 px, sin flotar),
60 px en móvil y 64 con carril (×1,5 como máximo con el texto). Siempre oscura
(`Brasa.obsidian`, acento `Brasa.accent`).

- **Progreso**: línea de brasa de 2 px en el borde superior: pista tenue, tramo
  encendido en degradado hasta la posición, resplandor y marca en la cabeza.
  Con `canSeek` la franja de 12 px es arrastrable (tocar o arrastrar mueve la
  marca, que con el cursor encima o al arrastrar crece a un cuadrado; `seek` se
  llama al soltar) y gana al deslizar de pista; semántica «Posición N %» con
  ajuste de 5 %. Sin `canSeek` solo se ve.
- **Texto**: artista en versalitas (11,5 px, tracking 1,4, ámbar) y pista debajo;
  hora `m:ss / m:ss` en monoespaciada (visible desde ~412 px; con texto grande se
  oculta). Con fallo del motor, `ERR` en rojo.
- **Teclas**: zona táctil de 44 px, trazo de 36–40. Reproducir es un cuadrado de
  borde ámbar que se rellena al sonar (anillo en búfer, reintento en rojo con
  fallo). Favorito es un glifo ámbar. Con carril (≥ 600 px) se añaden
  anterior/siguiente y la barra se divide en tres columnas con filetes.
- **Difuminado**: `BlurredCoverBackdrop(matchTheme: true)` (velo del tema, texto
  crema), viñeta oscura en los bordes y brillo de brasa sobre la línea; el artista
  pasa a 19 px, peso 800, tracking negativo. Las teclas y la línea llevan un
  fondo negro (55–60 %) para que el ámbar mantenga contraste ≥ 3.
- **Movimiento**: pulsar encoge a 0,92 al bajar el dedo (100 ms); con movimiento
  reducido solo baja la opacidad. La marca de la cabeza usa 120 ms.
- Pruebas: `test/mini_player/brasa_mini_player_test.dart`.

## Atelier (`atelier_mini_player.dart`)

Funda de disco acoplada al borde inferior, sin esquinas ni sombra: papel cálido
(`surfaceContainerLow`; oscuro, carbón cálido). 56 px en móvil y 64 con carril
(×1,5 como máximo con el texto, que el widget también recorta a ×1,5).

- **Funda**: portada cuadrada (46 px, 54 con carril, radio 6) con un vinilo que
  asoma por la derecha (disco negro, surcos, dos reflejos y etiqueta de acento).
  Con la pista sonando gira una vuelta cada 10 s (solo `transform`, un
  `RepaintBoundary`); en búfer, con error o con movimiento reducido, quieto.
- **Progreso**: la regla superior de 1 px es la línea de tiempo: tramo recorrido
  en acento y un nudo de 5 px en la posición. Solo indica; no se arrastra (5 px
  no es objetivo táctil y chocaría con el deslizar a los lados).
- **Texto**: título en la cara de display del tema (Newsreader 16,5/18 px,
  peso 500) y artista debajo en cursiva pequeña (14 px). Con fallo, el aviso
  «No se pudo reproducir» sustituye al artista.
- **Botones** (44 × 44): favorito y siguiente sin relleno; reproducir es un
  círculo de acento (en búfer, anillo; con movimiento reducido, reloj quieto).
  Con carril se añade «anterior». Bajo 330 px se omite el favorito.
- **Difuminado**: `BlurredCoverBackdrop(matchTheme: true)`: portada bajo el velo
  cálido del tema. El artista pasa arriba, en display de 22 px (26 con carril),
  tracking negativo, como la etiqueta de un disco; el título baja a cursiva
  pequeña. Sobre la portada el acento cede su sitio al color del texto garantizado
  (línea, nudo, play y favorito).
- **Movimiento**: pulsar hunde el botón a 0,93 (100 ms, ease-out); con
  movimiento reducido no hay hundimiento ni giro.
- Pruebas: `test/mini_player/atelier_mini_player_test.dart`.

## Slush (`slush_mini_player_v2.dart`)

Pegatina flotante: contorno de 2 px, sombra dura (3,4) fija detrás y esquinas de
28 (32 con carril). Móvil: dentro de `SlushBottomBar`, a su ancho (márgenes de
12), unos 72 px. Con carril: dock centrado de 720 px como máximo, en el cuerpo,
con el margen de pantalla de Slush; los gestos cubren solo el dock.

- **Color**: claro = losa de color vivo (menta, amarillo, lila o naranja, según
  el tono de `AccentScope`), tinta encima, play negro. Oscuro = losa `raised`
  con contorno crema; el vivo queda en el play y el progreso.
- **Progreso**: barra de 5 px en segmentos de 10 px con mando cuadrado de 10 px
  (solo indica; sin arrastre). Se pinta con un `CustomPaint` sin animación
  propia.
- **Texto**: título Inter 800 (14; 15 con carril) y artista debajo, ambos en
  tinta. Con fallo, «No se pudo reproducir» sustituye al artista.
- **Botones**: favorito de pegatina (círculo de 34 en zona de 44; rosa al
  marcarlo, con un salto de 260 ms), play circular con relieve (en búfer,
  anillo; con movimiento reducido, puntos quietos) y, desde 330 px de ancho
  interior, siguiente. Con carril se añade anterior. Sin permiso en Jam el play
  se desactiva y avisa «Lo controla X».
- **Difuminado**: `BlurredCoverBackdrop` bajo el contorno. El artista pasa a
  Bagel Fat One en mayúsculas (20; 26 con carril, escala ≤ 1,5) y el título a
  pequeño debajo; contornos, iconos y progreso toman el color de texto garantizado
  y el play y el mando conservan el color vivo. Si la portada aún no carga, se ve
  el aspecto normal.
- **Movimiento**: entra con opacidad y 8 px de recorrido (240 ms); al cambiar de
  pista el cover y el texto cruzan con `SlushMotion.fadeSlide`; el play cambia de
  icono con escala. Con movimiento reducido solo opacidad.
- Sustituye a `SlushMiniPlayer` (móvil) y `SlushPlayerBar` (carril): con carril
  ya no hay seek, volumen, cola, letras ni ecualizador en la barra; se llega a
  ellos desde las pestañas del reproductor (Vinilo, Letras, EQ, Cola).
- Pruebas: `test/mini_player/slush_mini_player_test.dart`.
