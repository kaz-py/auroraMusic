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
