import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../jam/jam_controller.dart';
import '../../jam/jam_models.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';
import '../studio/studio_components.dart';

/// Forma de las hojas inferiores en Modern (radio 24 arriba); null en Atelier
/// y en Slush (usa la del tema: radio 32 y borde).
ShapeBorder? jamSheetShape(BuildContext context) => isSlush(context)
    ? null
    : isBrasa(context)
    ? const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      )
    : isModern(context)
    ? const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      )
    : null;

/// Permisos y etiquetas derivados de la sesión; los usa la barra, el chip y el panel.
extension JamUi on JamController {
  bool get isStaff => role != JamRole.guest;
  bool get listeningTogether => service.mode == JamMode.synchronized;
  int get peopleCount => service.participants.where((p) => p.connected).length;
  String get code => service.invite?.code ?? '';
  String get roleLabel => switch (role) {
    JamRole.host => 'Host',
    JamRole.coHost => 'Co-host',
    JamRole.guest => 'Invitado',
  };
  String get modeLabel => listeningTogether ? 'Escuchando' : 'Solo añadir';
}

String jamRoleLabel(JamRole role) => switch (role) {
  JamRole.host => 'Host',
  JamRole.coHost => 'Co-host',
  JamRole.guest => 'Invitado',
};

/// Código de invitación y tiempos: cifras tabulares (`num`).
TextStyle jamCodeStyle(double size, {Color? color, double? spacing}) =>
    TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1.2,
      letterSpacing: spacing,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Botón sobre la tarjeta violeta de Slush: el anillo de foco del tema es
/// violeta y no se vería sobre el relleno; aquí es blanco (6,5:1).
ButtonStyle jamOnVioletButton(BuildContext context) => ButtonStyle(
  side: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.focused)
        ? const BorderSide(color: Slush.onViolet, width: SlushStroke.strong)
        : context.slush.border,
  ),
);

/// QR sobre #ffffff fijo (hace falta para escanearlo, también en oscuro) con
/// borde de control.
Widget slushQrFrame(BuildContext context, Widget qr) => DecoratedBox(
  decoration: BoxDecoration(
    color: const Color(0xffffffff),
    borderRadius: BorderRadius.circular(SlushRadius.r12),
    border: Border.fromBorderSide(context.slush.border),
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(SlushRadius.r8),
    child: qr,
  ),
);

/// Avatar con la inicial; el color sale del nombre para ser estable entre pantallas.
class JamAvatar extends StatelessWidget {
  const JamAvatar({
    super.key,
    required this.name,
    this.size = 28,
    this.muted,
    this.image,
  });
  final String name;

  /// Foto de perfil (PNG/JPEG ya validado); sin ella se muestra la inicial.
  final Uint8List? image;
  final double size;
  final bool? muted;
  static const _tones = [
    StudioPalette.orange,
    StudioPalette.peach,
    StudioPalette.parchment,
    StudioPalette.muted,
    Color(0xff8fb996),
    Color(0xff9db4d6),
  ];
  static const _brasaTones = [
    Color(0xffffd9a8),
    Color(0xffe8c4a0),
    Color(0xffc8b8aa),
    Color(0xffd9a57a),
    Color(0xffb8c9a6),
    Color(0xffa9b9cc),
  ];
  static const _modernTones = [
    Tracky.mint,
    Tracky.butter,
    Color(0xffb9d4f0),
    Color(0xffd8c8f0),
    Color(0xffc9e8a8),
    Color(0xffe8e7e5),
  ];
  static const _slushTones = [
    Slush.yellow,
    Slush.lilac,
    Slush.mint,
    Slush.orange,
    Color(0xff9db4f2),
  ];
  @override
  Widget build(BuildContext context) {
    final slush = isSlush(context);
    final modern = isModern(context);
    final brasa = isBrasa(context);
    final tones = slush
        ? _slushTones
        : brasa
        ? _brasaTones
        : modern
        ? _modernTones
        : _tones;
    final tone = tones[name.codeUnits.fold(0, (a, b) => a + b) % tones.length];
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final letter = Text(
      initial,
      style: TextStyle(
        color: slush
            ? Slush.ink
            : brasa
            ? Colors.black
            : modern
            ? Tracky.navy
            : StudioPalette.canvas,
        fontSize: size * .45,
        fontWeight: slush ? FontWeight.w800 : FontWeight.w700,
      ),
    );
    // Misma instancia de bytes => la caché de imágenes decodifica una vez.
    Widget photo(Widget fallback) => Image.memory(
      image!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * 3).round(),
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => Center(child: fallback),
    );
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone,
          shape: BoxShape.circle,
          border: slush
              ? Border.fromBorderSide(context.slush.border)
              : Border.all(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  width: brasa ? 1 : 2,
                ),
        ),
        child: image == null ? letter : ClipOval(child: photo(letter)),
      ),
    );
  }
}

class JamAvatarStack extends StatelessWidget {
  const JamAvatarStack({
    super.key,
    required this.names,
    this.images = const [],
    this.size = 24,
    this.max = 4,
  });
  final List<String> names;

  /// Fotos en paralelo a [names] (pueden faltar o ser null).
  final List<Uint8List?> images;
  final double size;
  final int max;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final slush = isSlush(context);
    final modern = isModern(context) || isBrasa(context);
    final shown = names.take(max).toList();
    final extra = names.length - shown.length;
    final step = size * .7;
    return SizedBox(
      width: step * (shown.length + (extra > 0 ? 1 : 0)) + size * .3,
      height: size,
      child: Stack(
        children: [
          for (final (i, name) in shown.indexed)
            Positioned(
              left: i * step,
              child: JamAvatar(
                name: name,
                size: size,
                image: i < images.length ? images[i] : null,
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * step,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: slush
                      ? context.slush.raised
                      : modern
                      ? colors.surfaceContainerHighest
                      : StudioPalette.high,
                  shape: BoxShape.circle,
                  border: slush
                      ? Border.fromBorderSide(context.slush.border)
                      : Border.all(
                          color: modern
                              ? colors.surfaceContainerLowest
                              : StudioPalette.well,
                          width: 2,
                        ),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: slush ? 11 : size * .38,
                    fontWeight: slush ? FontWeight.w800 : null,
                    color: slush
                        ? context.slush.ink
                        : modern
                        ? colors.onSurface
                        : StudioPalette.ink,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Píldora de la barra inferior y del chip: avatares + «Jam · N» + rol/modo.
class JamPill extends StatelessWidget {
  const JamPill({
    super.key,
    required this.jam,
    required this.onTap,
    this.compact = false,
  });
  final JamController jam;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final people = [
      for (final p in jam.service.participants)
        if (p.connected) p,
    ];
    final names = [for (final p in people) p.name];
    final label =
        'Jam · ${jam.peopleCount} ${jam.peopleCount == 1 ? 'persona' : 'personas'}';
    return Semantics(
      button: true,
      label:
          '$label, ${jam.roleLabel}, ${jam.modeLabel}. Abrir panel de la Jam',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Abrir la Jam · ${jam.roleLabel} · ${jam.modeLabel}',
        child: Material(
          color: isBrasa(context)
              ? colors.surfaceContainerHigh
              : isModern(context)
              ? colors.surfaceContainerLow
              : colors.surfaceContainerHigh,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: StadiumBorder(
            side: isSlush(context)
                ? context.slush.border
                : isBrasa(context)
                ? BorderSide.none
                : isModern(context)
                ? BorderSide(color: colors.outlineVariant)
                : BorderSide(color: colors.primaryContainer.withAlpha(120)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    JamAvatarStack(
                      names: names,
                      images: [for (final p in people) jam.avatarOf(p.id)],
                      size: 22,
                      max: compact ? 2 : 3,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            compact
                                ? 'Jam · ${jam.peopleCount} · ${jam.roleLabel}'
                                : label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!compact)
                            Text(
                              '${jam.roleLabel} · ${jam.modeLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isSlush(context) ? 12 : 10,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
