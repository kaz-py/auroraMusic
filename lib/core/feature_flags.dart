import 'package:flutter/foundation.dart';

/// Servicios que dependen de Supabase: cuenta y sincronización en la nube,
/// amigos y Jam por internet. **Desactivados temporalmente** (el proyecto
/// superó el plan gratuito). Para volver a activarlos basta con poner `true`:
/// el código sigue completo, y Aurora lo detecta y reconecta solo cuando el
/// servidor responde. Mientras tanto la Jam por red local (QR) y la
/// transferencia de biblioteca por QR siguen funcionando.
const bool kSupabaseEnabled = false;

bool? _testOverride;

/// Lo que usa la aplicación: [kSupabaseEnabled], salvo en pruebas.
bool get supabaseServicesEnabled => _testOverride ?? kSupabaseEnabled;

/// Solo para pruebas: fuerza el interruptor (`null` = el valor real).
@visibleForTesting
set supabaseServicesOverride(bool? value) => _testOverride = value;
