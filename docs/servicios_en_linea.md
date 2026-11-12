# Servicios en línea (Supabase) y modo local

Aurora usa Supabase para la **cuenta** y la sincronización, los **amigos** y la **Jam por internet**. Todo lo demás (reproducir, biblioteca, DJ, letras, Jam por red local, transferencia por QR) funciona sin él.

## Interruptor general

`lib/core/feature_flags.dart` → `kSupabaseEnabled`. Está en **`false`** desde que el proyecto superó el plan gratuito. Apagado:

- no se crea el cliente de Supabase ni se contacta con el servidor (`connectAccount` sale al principio);
- se ocultan **Amigos** (barra lateral, menús y botones de «enviar a un amigo») y la sección **Cuenta** de Ajustes; «Servicios en línea» explica que está desactivado;
- la Jam automática se crea **en red local** (código QR); «Jam en línea» y unirse con un código de internet avisan de que está desactivado.

Para reactivarlo: `kSupabaseEnabled = true` (y las credenciales `AURORA_SUPABASE_URL` / `AURORA_SUPABASE_ANON_KEY` de siempre). El código sigue completo.

## Cuando está activado: detección del servidor

`OnlineStatus` (`lib/core/online_status.dart`) hace una petición a `/auth/v1/health` (4 s de tope) y recuerda el resultado: 5 min si responde, 2 min si no. Si el servidor está pausado o sin cuota:

- el arranque **no espera** a la red (antes la cuenta se conectaba en la ruta del primer frame);
- la Jam automática usa la red local y las de «en línea» explican el motivo;
- se vuelve a probar sola y, al volver el servidor, se reconectan la cuenta y la sincronización.

Ajustes → Cuenta y servicios → **Servicios en línea** deja elegir «solo local».

## Qué gastaba la cuota (y qué se cambió)

Medido por lectura del código, no con métricas del proyecto:

| Origen | Antes | Ahora |
|---|---|---|
| Jam en línea: publicación del anfitrión | cada 1 s, multiplicada por invitado (≈100 000 mensajes por hora con 5 personas) | solo si cambia algo (pista, play/pausa, salto) y un fotograma clave cada 10 s |
| Jam en línea: ping del invitado | cada 8 s (3 escrituras + 1 mensaje) | cada 20 s |
| Sync de cuenta tras cada cambio | espera 3 s, baja 4 tablas y sube | espera 30 s y **solo sube**; baja como mucho cada 10 min |
| Historial y gusto del DJ | se subían con cada reproducción | como mucho cada 10 min |

Pendiente (no hecho): usuarios anónimos de la Jam (la sesión no se guarda entre arranques, puede crear uno nuevo cada vez), subir playlists como lista de ids en vez del JSON de cada pista, y hash del vector de gusto para no subir lo idéntico.

## Transferir la biblioteca por QR (misma red)

Ajustes → Cuenta y servicios → **Transferir por QR**. Sin internet, sin cuenta y sin servidor:

1. En el dispositivo origen: **Enviar**. Se abre un servidor de solo lectura en tu IP privada (puerto aleatorio) y se muestra un QR que caduca a los 5 minutos.
2. En el destino: **Recibir**, escanear el QR (Android) o pegar el código (`aurora-sync:…`).
3. Viajan favoritos, listas, historial y gusto del DJ. El destino recuerda hasta dónde recibió de cada origen y **la siguiente vez solo baja lo que cambió**; lo más reciente gana, con lápidas para lo borrado.

Seguridad: el código solo apunta a direcciones privadas (10.x, 172.16–31.x, 192.168.x), lleva una clave aleatoria de 256 bits que se compara en tiempo constante, el servidor caduca solo, limita las peticiones y es de solo lectura. Va por HTTP en la red local (el QR es el secreto): no lo uses en una Wi-Fi pública. Lo anterior a cualquier sincronización (marca 0) se reenvía en cada transferencia; es poco y no se duplica.

Pruebas: `test/online_status_test.dart`, `test/jam_offline_test.dart`, `test/supabase_disabled_test.dart`, `test/lan_sync_test.dart`, `test/lan_sync_panel_test.dart`, `test/account_test.dart`.
