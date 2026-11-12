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
páginas (`SlushTopBar`, `SlushBottomBar`, `SlushPage`, `SlushEqQueue`…).

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
