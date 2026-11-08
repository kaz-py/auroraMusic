import 'dart:async';

import 'package:aurora_music/bridge/frb_generated.dart';

/// Carga el motor Rust una vez por archivo de prueba. Requiere compilarlo antes:
/// `cargo build --release --manifest-path rust/Cargo.toml`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await RustLib.init();
  await testMain();
}
