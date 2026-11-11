# Actualizaciones de Aurora (Windows)

## Causa raíz del fallo «la ventana desaparece y la versión no cambia» (1.2.1)

Cadena verificada leyendo el código (no reproducida: había una instancia del usuario viva):

1. `UpdateController.install()` lanzaba el instalador (`/VERYSILENT … /CLOSEAPPLICATIONS`, desacoplado) y
   llamaba a `requestHardExit()` → método nativo `hardExit`.
2. `hardExit` solo ponía `real_exit_ = true` y enviaba `WM_CLOSE`. `WM_CLOSE` entra en
   `RequestClose()`, que invoca `confirmClose` en Dart. El temporizador de seguridad de 3 s
   solo se armaba con la guardia de cierre desactivada, y el shell la activaba siempre que
   el reproductor web (ya retirado) estaba montado. Es decir, justo el caso normal: sin
   vigilante. La guardia (`guardClose`) desapareció con el reproductor web y el temporizador
   es ahora incondicional.
3. El cierre esperaba la confirmación de Dart. Si algo no respondía, el proceso nunca llegaba
   a destruir la ventana; si Dart devolvía `false`, el runner hace `real_exit_ = false` y el
   siguiente cierre oculta a la bandeja. Además, aunque la ventana se destruyera, el proceso
   podía seguir vivo (motor de audio) sin ventana.
4. El instalador Inno con `/CLOSEAPPLICATIONS` no consigue cerrar un `aurora_music.exe`
   vivo y escondido; con `/VERYSILENT /SUPPRESSMSGBOXES` aborta sin mostrar nada ni escribir
   log. Resultado: sin ventana, proceso vivo, versión vieja, ningún error.

No se pudo confirmar cuál de los eslabones de (3) fue el que falló en el equipo del usuario;
el defecto de diseño (cierre sin vigilante y sin feedback) es común a todos.

## Solución

- **Runner** (`flutter_window.cpp`): `hardExit` además arma `ArmExitWatchdog()`, un hilo nativo
  que a los 3 s guarda la geometría, quita el icono de bandeja, libera el mutex de instancia
  única y llama a `ExitProcess(0)` (con otro hilo que hace `TerminateProcess` a los 2 s más).
  Independiente de Dart. La X (siempre a la bandeja), Alt+F4,
  `SC_CLOSE` y «Salir» de la bandeja **no** lo arman.
- **Dart**: `requestHardExit()` va con `.timeout(3 s)` y cae a `exit(0)`.
- **Instalador**: `/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS
  /FORCECLOSEAPPLICATIONS /LOG="<temp>\aurora_update\install.log"` (ventana de progreso).
  El `[Run]` con `Check: WizardSilent` relanza Aurora también con `/SILENT`; la entrada
  `postinstall` lleva `skipifsilent`, así que no aparece página final. No se usa `AppMutex`
  (en silencio bloquearía la instalación); `FORCECLOSEAPPLICATIONS` mata la instancia vieja,
  por lo que el relanzamiento no lo absorbe una instancia anterior.
- **Estado en UI**: fase `installing` → «Instalando la actualización… Aurora se reiniciará sola.»
- **Verificación posterior**: antes de lanzar se guarda `pendingUpdate` (versión objetivo) en
  SharedPreferences. Al arrancar: si la versión instalada ≥ objetivo → «Actualizada a X», se
  borran instaladores viejos e `install.log`; si no → «La actualización no se completó» con
  «Abrir el instalador» (Explorador) y la ruta de `install.log`, que se conservan.
- Android no cambia (FileProvider + instalador del sistema).

## Probar a mano (instala 1.2.2 y publica una versión siguiente)

1. En 1.2.2, con música sonando, «Actualizar ahora» → debe verse «Instalando…», cerrarse
   Aurora, aparecer la ventana de progreso de Inno y reabrirse Aurora sola, con banner
   «Actualizada a X». Comprobar en el Administrador de tareas que no queda proceso viejo.
2. Fallo: dejar el instalador sin poder ejecutarse (p. ej. bloquear el .exe) → al reabrir
   debe salir «La actualización no se completó» con la ruta del log.
