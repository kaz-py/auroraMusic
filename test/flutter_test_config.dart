import 'dart:async';

import 'package:aurora_music/bridge/frb_generated.dart';
import 'package:aurora_music/core/feature_flags.dart';

/// Carga el motor Rust una vez por archivo de prueba. Requiere compilarlo antes:
/// `cargo build --release --manifest-path rust/Cargo.toml`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await RustLib.init();
  // En producción Supabase está apagado (kSupabaseEnabled); las pruebas de
  // amigos, cuenta y Jam en línea lo necesitan encendido.
  supabaseServicesOverride = true;
  await testMain();
}
