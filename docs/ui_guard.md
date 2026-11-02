# Guarda de interfaz (visibilidad y responsive)

`test/ui_guard/ui_guard_test.dart` bombea `AuroraApp` en una matriz y falla si
algo deja de verse o de caber. Evita que un cambio de tema o de layout rompa
otro tema, otra anchura o el texto grande sin que nadie lo note.

## Qué comprueba (por tema × modo × anchura × escala × pantalla)

| Tipo | Regla |
| --- | --- |
| `exception` | Ninguna excepción del framework: desbordes (`RenderFlex overflowed`), errores de layout/build. |
| `contrast` | Texto e iconos con contraste >= 3:1 contra su fondo resuelto (`legibility_scan.dart`, el mismo escáner de `slush_legibility_test.dart`). |
| `hit` | Solo en móvil (< 600 px): botones, `ListTile`, chips, `InkWell` y `GestureDetector` con `onTap` visibles miden >= 40x40 px lógicos. La barra de título de escritorio (`StudioTitleBar`) se excluye: es de ratón. |
| `clip` | Ningún texto/imagen visible cruza el borde horizontal de la pantalla, salvo dentro de un scroll horizontal o de un contenedor que lo recorta dentro de la pantalla. |

Matriz completa: Atelier, Modern y Slush en claro y oscuro, Brasa solo oscuro ·
360×740, 412×915, 600×960, 900×700, 1440×900, 1920×1080 · escala de texto 1.0 y
2.0 · Inicio, Búsqueda, Biblioteca, DJ, Jam, Cola/EQ, Vinilo, Ajustes,
Descargas, Artistas, Amigos, Letras y Ecualizador.

## Niveles

* **quick** (por defecto; lo ejecuta `flutter test`): 360/900/1440 × escala 1 y 2
  × Slush claro/oscuro + Atelier claro × Inicio, Búsqueda, DJ, Jam, Cola/EQ,
  Vinilo. Unos 15-30 s.
* **full**: todo lo anterior. Bajo demanda:

```
flutter test --no-pub test/ui_guard --dart-define=UI_GUARD=full
# o con variable de entorno
UI_GUARD=full flutter test --no-pub test/ui_guard
```

Para una sola combinación: `--plain-name "slush/dark 360x740 x2.0"`.

Cada fallo se imprime como `UI-GUARD ✗ <tema>/<modo> <ancho>px x<escala> ·
<pantalla>  [<tipo>] <detalle>` (con archivo y línea en los desbordes).

## Fallos conocidos

`test/ui_guard/known_issues.dart` lista los fallos que la app tiene hoy, cada
uno con archivo y motivo. Son TODOs: **la lista solo puede encogerse**. Si una
entrada se ejercita y ya no se reproduce, el último test de la guarda falla con
`ya arreglado, borra "<id>"`: bórrala. Nunca añadas una entrada para tapar un
fallo nuevo; arréglalo.

## Hook de pre-commit (opcional)

`scripts/hooks/pre-commit` corre el nivel quick solo si el commit toca
`lib/ui/`, `lib/theme/`, `lib/main.dart` o `test/ui_guard/`, y rechaza el
commit listando los fallos. Es opt-in, por clon:

```
powershell -File scripts/install_hooks.ps1     # Windows
sh scripts/install_hooks.sh                    # Git Bash / Linux / macOS
```

Ambos hacen `git config core.hooksPath scripts/hooks`; se deshace con
`git config --unset core.hooksPath`. Flutter se busca en `$FLUTTER`,
`C:/flutter/flutter/bin/flutter.bat` y `flutter` del PATH; si no hay ninguno
avisa y no bloquea. Para saltarlo: `git commit --no-verify`. Prueba el árbol de
trabajo, no el índice. Antes de ejecutar borra (o renombra, si está bloqueado
por otro `flutter test`) `build/native_assets/windows/sqlite3.dll`.

## Notas de diseño de la prueba

* Se navega con el callback `onNavigate` de la barra superior (`SlushTopBar` /
  `StudioTitleBar`) a 1440×900 y se vuelve al tamaño del caso: el shell solo
  expone todas las secciones con barra/rail (>= 600 px).
* Las excepciones se recogen todas (no solo la primera) con un
  `FlutterError.onError` propio, que se restaura antes de `fail`.
* Sin ajustes de plataforma ni fuentes reales de dispositivo: un desborde de
  1-2 px puede deberse a la fuente de test; si no es arreglable, va a
  `known_issues.dart` con ese motivo.
* No cubre hardware, audio real ni capturas; es una guarda geométrica.

## Estado del nivel full

El nivel full no está inventariado: solo quick es el gate del hook y el único
que se ha ejecutado completo y está en verde. Full es lento (84 casos × 13
pantallas) y puede destapar fallos de Modern, Brasa y de otras anchuras que aún
no figuran en `known_issues.dart`; trátalos como pendientes, no como regresión.
Las pantallas con animación infinita se miden tras 3 s sin estabilizarse.
