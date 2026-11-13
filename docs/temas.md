# Temas: cómo añadir o ser dueño de uno

Aurora tiene cuatro temas (`AuroraThemeKind`: atelier, modern, brasa, slush).
`themeKindOf(context)` en `lib/theme/aurora_tokens.dart` es el único resolvedor
(Slush lleva también `ModernMarker`, por eso se comprueba antes que Modern).
Nada fuera de ese archivo debe usar `isSlush`/`isModern`/`isBrasa` para elegir
una pantalla entera: se registra un objeto por tema.

## Mapa de archivos por tema

| Pieza | Archivo (`<t>` = tema) | Contrato |
| --- | --- | --- |
| Colores, tipografía, `ThemeData` | `lib/theme/<t>_theme.dart` | `auroraTheme`/`modernTheme`/`brasaTheme`/`slushTheme` |
| Chrome del shell | `lib/ui/shell/chrome_<t>.dart` | `ShellChrome` (registro `shellChromes`) |
| Cuerpo de barra de título y sidebar | `lib/ui/shell/bars_<t>.dart` | `<t>TitleBar(...)` / `<t>Sidebar(...)`, los llama `StudioTitleBar`/`StudioSidebar` |
| Inicio | `lib/ui/home/home_<t>.dart` | `HomeTheme` (registro `homeThemes`) |
| Reproductor completo (sección 4) | `lib/ui/player/player_<t>.dart` | `PlayerTheme` (registro `playerThemes`) |
| Cola y panel derecho | `lib/ui/right_panel/right_panel_<t>.dart` | `RightPanelTheme` (registro `rightPanelThemes`) |
| Mini reproductor | `lib/ui/mini_player/<t>_mini_player.dart` | `MiniPlayerTheme` (`miniPlayerThemes`) |
| Chat de amigos | `lib/ui/friends_chat/<t>_chat.dart` | `ChatTheme` (`chatThemes`) |

Slush (`slush_mini_player_v2.dart`, `lib/ui/slush/*`) además tiene sus propias
páginas (`SlushDesktopHeader`, `SlushBottomBar`, `SlushPage`, `SlushEqQueue`…).

## Chrome del shell (`shell_chrome.dart`)

`AuroraShell.build()` solo elige `shellChromeFor(themeKindOf(context))` y
ensambla. Un tema implementa `ShellChrome`:

- `topBar`, `sidebar`, `aside`, `header` → `Widget?` (`null`: no hay pieza).
- `errorBanner`, `bottomNavigation` → `Widget` (la navegación inferior solo se
  pide sin carril, ancho < 600).
- Opcionales: `contentFrame` (envuelve el cuerpo), `pageTransition` (entre
  secciones), `ownsPageFrame`/`pageFrame` (el tema pinta el titular y marco de
  ciertas secciones, como `SlushPage`), `sectionOverride` (página propia para
  cola 5 y ecualizador 13).
- `ShellScope` trae sección activa, anchos (`rail` ≥ 600, `wide` ≥ 900,
  `desktop` ≥ 1200), controlador, Jam, insignia de amigos, callbacks
  (`onNavigate`, `onProfile`, `onSearch`, `onStartJam`, `onCreatePlaylist`…) y
  `miniPlayer(placement)`.
- Secciones: `shell_sections.dart` (`shellSectionTitles`, `shellSectionIcons`,
  `primarySections(kind, mobile: …)`). Los ids no se renumeran.
- Lo que sea solo de ratón (barra de título de escritorio) va dentro de
  `MouseOnlyRegion`: la guarda de objetivos táctiles no lo exige de 44 px.
- La sección 6 (modo letras) **queda fuera** de todo chrome: `AuroraShell` la
  resuelve antes y no se debe mover dentro de `ShellChrome`.

## Añadir un tema nuevo

1. Valor nuevo en `AuroraThemeKind` y su rama en `themeKindOf`.
2. Un objeto por registro: `shellChromes`, `homeThemes`, `playerThemes`,
   `rightPanelThemes`, `miniPlayerThemes`, `chatThemes` (los mapas de mini
   reproductor y chat usan `kind.name` como clave).
3. `ThemeData` con su marcador (`ThemeExtension`) en `lib/theme/` y su selección
   en `lib/main.dart`.

## Navegación en tests

`ShellNav` (InheritedWidget que monta el shell por encima de todo):
`tester.widget<ShellNav>(find.byType(ShellNav)).navigate(sección)` y
`.section`. Así la guarda de UI navega igual en los cuatro temas.

## Zonas compartidas (tocar con cuidado)

`vinyl_player.dart` (estado, giro, seek, vista casete), `home_music_page.dart`
(datos), `queue_panel.dart` y `studio/session_aside.dart` (lógica),
`shell_header.dart` y `shell_rail.dart` (los usan tres temas), y las páginas
internas de `aurora_shell.dart` (buscar, biblioteca, ajustes, descargas), que
todavía ramifican por tema. El modo letras (`artist_mode.dart`, `lib/lyrics/*`,
`mini_player/blurred_cover_backdrop.dart`, `cover_tone.dart`,
`cover_backdrop_source.dart`) hereda `titleMedium`/`bodyMedium`/`labelSmall`,
`fontFamily` e `IconButton`/`Slider`/`Tooltip` del tema activo: no cambiar esos
valores globales.

## Brasa («Salón con estufa»)

Solo oscuro (humo cálido); una única brasa marca lo vivo (activo, suena,
progreso). Prototipo: `Aurora-prototipos/brasa/` (`DISENO.md`).

- **Tokens** (`lib/theme/brasa_theme.dart`, clase `Brasa`): `void_` #0F0A08
  (sidebar), `obsidian` #17110D (lienzo), `graphite` #211914, `ash` #2C2219,
  `surface3` #382C20, `bar` #251B15, `cream` #F2E6D8, `cloud` #BBA997, `steel`
  #968675, `amber` #E8A24A (datos técnicos), `ember` #FF7A3D (= `Brasa.accent`,
  ya no se tiñe con la portada), `onEmber` #1A0C05, `Brasa.filament`.
  Tipografía: `Brasa.serif` (Fraunces 600, −0,02 em), `Brasa.sans` (DM Sans),
  `Brasa.mono` (DM Mono, versalitas con tracking .14).
- **Firma**: el filamento (`BrasaFilament`, `lib/theme/brasa_widgets.dart`:
  degradado `#B3401F → #FF7A3D → #E8A24A`, brillo y cabeza con halo) y el
  resplandor radial tras la portada (`BrasaGlow`: degradado estático dentro de
  un `RepaintBoundary`, sin blur ni `BackdropFilter`).
- **Escritorio**: barra superior (`bars_brasa.dart`: marca, búsqueda, Jam,
  perfil, ventana) sobre el tono de la sidebar de 300 px por tono, sin bordes
  (destinos con atajo en mono, etiquetas con punto de brasa, listas con muestra
  de color, Ajustes y tarjeta del motor al pie; activo = fondo `graphite` +
  barra de brasa con brillo + icono naranja).
- **Móvil**: pestañas Inicio · Buscar · DJ · Biblioteca · Más (indicador pill
  de brasa al 20 %, etiquetas siempre visibles). «Más» abre una hoja con perfil,
  importar y el resto de vistas (`showBrasaMoreSheet` en `chrome_brasa.dart`).
  `primarySections(brasa, mobile: true)` devuelve solo las cuatro primeras.
- **Modo letra**: `lyrics_skin_brasa.dart` (Fraunces, palabra de brasa en la
  línea activa, fondo desenfocado cacheado sin `BackdropFilter`).
- **Huecos conocidos**: la tarjeta de la sidebar dice «Motor de audio» (el
  prototipo, «Sincronización DAC», no tiene dato real); el chip de carpeta y
  «Modo Foco / Sueño» de la sidebar no se muestran (sin destino propio).
- **Diferencias deliberadas con el prototipo**: Aurora conserva la barra superior
  compartida (búsqueda, Jam, perfil, ventana) que el prototipo no dibuja; el
  saludo no lleva nombre (no hay dato de perfil); los chips técnicos del reproductor
  (FLAC 24/96, EQ…) salen solo con datos reales de la pista; el reproductor de
  escritorio conserva su tarjeta de transporte propia (vista portada/vinilo/casete)
  además de la barra global; la portada de escritorio mide hasta 380 según el ancho
  libre y la de móvil hasta 268 según la altura libre (`player_brasa.dart`).
- **Revisión visual** (render de test a 1440x900 y 390x844 contra los PNG): inicio,
  reproductor y modo letra coinciden en estructura; no hay capturas de Android real.

## Modern («Cristal y aura de portada»)

Lienzo casi negro `#0B0D12`; la portada tiñe el entorno (aura) y todo lo
interactivo es cristal fino. Un solo acento azul `#6EA8FF` (play, activo,
progreso); menta `#86E0C1` solo para señal/formato, coral `#FF6B6B` solo para
«me gusta». Prototipo: `Aurora-prototipos/modern/` (`DISENO.md`).

- **Tokens y piezas** (`lib/theme/modern_cristal.dart`): `Cristal` (paletas
  `darkPalette`/`lightPalette`, `Cristal.ui` = Manrope, `Cristal.mono` = Geist
  Mono), `ModernGlass` (cristal = relleno translúcido + borde + brillo interior,
  **sin `BackdropFilter`**), `ModernAura` (fondo con 2 manchas de la portada),
  `ModernWaveSeekBar` (onda de barras; picos deterministas por pista con
  `modernPeaks(seed, n)`, no hay análisis de audio real), `ModernSignalChip`
  (formato en menta + mono). `modern_widgets.dart` sigue compartido con Slush
  (siempre `isSlush` antes que `isModern`).
- **Escritorio**: `modern_sidebar.dart` (248 / riel 76 con tooltip + atajo, activo
  = píldora azul + barra de 3 px, pie con estado del motor), `modern_top_bar.dart`,
  barra flotante `modern_mini_desktop.dart` (88 px: pista · transporte con onda ·
  señal/EQ/letras/cola/volumen; el volumen solo desde ~1120 px). Inicio:
  `modern_home_page.dart` (saludo, hero «Seguir escuchando», tarjeta DJ,
  recomendaciones, descargas en lista). Reproduciendo: `player_modern.dart` +
  panel derecho `modern_aside_panel.dart` (Cola / Ahora suena / Letras + pie con
  Jam y sueño) que `chrome_modern.dart` monta en la sección 4; Inicio no lleva panel.
- **Móvil**: `modern_mobile_nav.dart` (5 destinos, píldora 56x30; sin barra en el
  reproductor), mini `modern_mini_player.dart` (64 px con tinte de portada),
  reproductor `modern_player_mobile.dart` (portada hasta 296 según la altura libre,
  onda 44, play «squircle» 72, 5 utilidades de 48 dp, hoja de letras; el ⋯ abre la
  tarjeta de la canción con Ver portada/vinilo/casete).
- **Modo letra**: `lyrics_skin_modern.dart` (aura + portada ya desenfocada de la
  caché, Manrope 800, activa 44/32 con halo, onda de 22 px, play azul con glow).
- **Efectos**: ninguna capa de blur en vivo (el cristal es relleno plano) y el
  desenfoque de portada sale de la caché; no existe un perfil `reduceEffects`.
- **Huecos conocidos**: el pie de la sidebar dice «Motor de reproducción listo»
  (la «sincronización DAC no medida» del prototipo no tiene dato); el riel de 76 px
  no se expande al pasar el ratón (solo tooltip con atajo); la barra flotante
  no se dibuja en el reproductor de escritorio (`aurora_shell.dart` oculta el
  transporte en la sección 4, fuera del alcance del tema); el nombre del saludo viene
  de `profileName` (vacío = solo «Buenas noches»); no hay fila «Música · D:\Audio».
- **Revisión visual**: `test/modern_views_test.dart` (con `MODERN_SHOTS=1` vuelca
  PNG a `build/modern-review/`) renderiza inicio, reproduciendo, cola y modo letra a
  1440x900 (x1 y x2), 390x844, 360x740 y 360 x2 sin excepciones.

## Atelier («Papel y tinta»)

- Tokens y tipografía: `lib/theme/atelier_theme.dart` (`AtelierTokens`; Newsreader, Inter, IBM Plex Mono). Texto terracota `#9C4222` (`accentText`); `#B4532A` solo en botones y elementos gráficos. En Android `mono()` sube a 12 px mínimo. Los estados (hover, selección, foco) usan la receta común de `AuroraStates.from` con terracota fija para cumplir `test/contrast_test.dart`.
- Piezas comunes: `lib/ui/shell/atelier_widgets.dart` (chip de formato, cabecera «Nº 01», `AtelierLine` = filete de progreso con rombo, sello de calidad).
- Shell: `chrome_atelier.dart` (sidebar 248, panel derecho 352, bottom nav) y `bars_atelier.dart` (barra de 76 con filete = progreso, mini 60). El panel derecho también se ve en Reproduciendo (sección 4) en escritorio; en móvil esa vista no lleva bottom nav (trae su pie «Cola · N pistas»).
- Vistas: `home_atelier.dart`, `player_atelier.dart`, `right_panel_atelier.dart`, `lyrics_skin_atelier.dart` (papel con manchas, variante noche), `mini_player/atelier_mini_player.dart`.
- Móvil: la pestaña «Buscar» lleva el tooltip «Buscar música» mientras no está activa (lo esperan los tests de navegación).

### Diferencias con el prototipo (decididas)
- Inicio: el saludo lleva nombre solo si existe perfil; sin datos reales el DJ/recomendaciones muestran el estado vacío honesto. En móvil el hero lleva además «Añadir a la cola» y el chip de formato (el prototipo solo «Reanudar»); el DJ es un carrusel de portadas.
- Reproduciendo (escritorio): la barra inferior la oculta el host del mini player en la sección 4, así que la página conserva su propia línea de progreso y transporte; la letra es un extracto sincronizado (LRCLIB) con marcador terracota al 22 %. Sin letra: «Sin letra sincronizada para esta pista».
- Sello de calidad: dice «SIN PÉRDIDA · FLAC 24/96» solo con formato sin pérdida real (extensión del archivo); para streams muestra el formato real («STREAM») en un aro «AURORA · FORMATO». No se inventa 24/96 ni «DAC medida» («Sincronización DAC · no medida» es el estado real).
- Modo letra: marcador de línea activa a altura completa (`backgroundColor` por línea, como pide el diseño), no solo la banda inferior del PNG. En ventana estrecha con controles de ventana o texto grande la etiqueta de salir es «Salir».
- Mini player: sin vinilo giratorio (el diseño nuevo usa filete + rombo).

### Huecos conocidos
- No se pudo verificar visualmente con portadas reales ni con el fondo de 3 manchas (las pruebas no cargan imágenes de red).
- Las capturas del harness usan fuentes cargadas a mano (pesos 500/600 de Inter se ven con sustituto en test).

## Slush 2.0 («Pegatinas, lila y lima»)

- Tokens: `lib/theme/slush_theme.dart` (`Slush`, `SlushPalette` claro/oscuro) y `slush_tokens.dart` (titulares Bricolage Grotesque 800, `slushMono` Geist Mono). Claro: tinta `#14101F`, papel `#FFFDF8`, fondo fijo `#E9E0FF` con trama de puntos (`SlushDotBackdrop`, un `CustomPaint` cacheado), lila `#C4B0FF` (`lilacHero`), violeta `#5B3FE0` (activo y progreso), lima `#D8FF5C` (lo que suena: Play, pista actual, thumb, subrayado de la letra). Oscuro: `SlushPalette.dark` sigue vigente (cremas sobre capas `screen`<`paper`<`raised`).
- Shell: `chrome_slush.dart` + `bars_slush.dart` (sidebar flotante 272 con logo-pegatina, píldoras de nav —activa violeta—, mosaico 2x3 de tiles de color con `minHeight`, píldora «Música · ruta»; panel derecho `slush_aside.dart` Ahora suena / Cola / Letras solo en la sección 4). Barra superior: `SlushDesktopHeader` (búsqueda en píldora, chip lima de Jam, perfil). El rótulo de Jam solo se muestra con textScale <= 1,5.
- Inicio: `home_slush.dart` + `slush_home.dart` (hero lila con portada 172 y Play lima 60, DJ amarillo con onda, ánimos de color, recomendaciones giradas ±2°). La tarjeta hero no usa `LayoutBuilder` (vive en un `IntrinsicHeight`): el ancho se lo pasa `SlushHome`.
- Reproduciendo (`slush_player.dart`): escritorio = tarjeta lila con portada + vinilo asomando por detrás (casete: solo la pieza), etiquetas (Ahora suena, FLAC/LOCAL/YOUTUBE, origen), chips Me gusta/EQ/Dormir/Jam, tarjeta de letras (subrayado lima en la línea activa) y tarjeta de transporte (seek violeta, thumb lima, Play lima). Móvil = fondo lila con puntos, cabecera redonda, portada con pegatina de formato, titular + corazón rosa, tres líneas de letra, seek, 5 controles con Play squircle 76 (radio 30), chips y hoja de cola (`queue-peek`, abre la sección 5).
- Modo letra: `lyrics_skin_slush.dart` (portada borrosa + velo violeta que envuelve el contenido, puntos, botones de papel, «Salir» lima).
- Móvil: `slush_nav.dart` (cápsula flotante Inicio·Buscar·Biblioteca·DJ·Más con objetivos de 56, hoja «Más») y `slush_mobile.dart`; mini lila de 64 en `mini_player/slush_mini_player_v2.dart`.
- Modo oscuro: `SlushPalette.dark` y `slushScreenColor(dark: true)` (tinte leve de la portada). El Jam/EQ/Vinilo siguen cubiertos por `test/slush_dark_test.dart`.
- Huecos conocidos: no hay etiqueta «DAC · 96 kHz» ni «Racha: 6 días» (la app no mide la DAC ni cuenta rachas); el formato es FLAC solo si el archivo local lo es (si no, LOCAL/YOUTUBE); la barra de reproducción de escritorio no se dibuja en la sección 4 (`MiniPlayerHost.isVisible` oculta el mini ahí; el transporte va en la propia pantalla); la hoja de cola móvil abre la pantalla Cola, no es una hoja arrastrable; el vinilo no asoma en móvil (el prototipo tampoco lo dibuja).
