import 'package:flutter/material.dart';

/// SnackBar flotante que SIEMPRE se cierra solo. El color, el texto y la forma
/// salen del `snackBarTheme` de cada tema; aquí solo van el ancho y la acción.
SnackBar auroraSnackBar(
  BuildContext context,
  Widget content, {
  String? label,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  return SnackBar(
    content: content,
    duration: duration,
    persist: false,
    behavior: SnackBarBehavior
        .floating, // width exige flotante; también sin snackBarTheme (tests con MaterialApp pelado)
    width: MediaQuery.sizeOf(context).width >= 600 ? 420 : null,
    action: label == null
        ? null
        : SnackBarAction(label: label, onPressed: onAction ?? () {}),
  );
}

/// Muestra un SnackBar (con acción opcional) que SIEMPRE se cierra solo: Flutter
/// deja `persist = action != null` por defecto y el aviso no desaparecería.
void showUndoSnackBar(
  ScaffoldMessengerState? messenger,
  Widget content, {
  String? label,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 5),
}) {
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    auroraSnackBar(
      messenger.context,
      content,
      label: label,
      onAction: onAction,
      duration: duration,
    ),
  );
}
