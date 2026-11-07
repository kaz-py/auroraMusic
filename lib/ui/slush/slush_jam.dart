import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../jam/jam_controller.dart';
import '../../jam/jam_models.dart';
import '../../jam/jam_service.dart';
import '../../theme/accent_transition.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import '../jam/jam_add_sheet.dart';
import '../jam/jam_flows.dart';
import '../undo_snackbar.dart';
import '../jam/jam_qr_code.dart';
import '../jam/jam_session_panel.dart';
import '../jam/jam_widgets.dart';

const _tones = [
  Slush.yellow,
  Slush.lilac,
  Slush.mint,
  Slush.orange,
  Color(0xff9db4f2),
];
Color _tone(String name) =>
    _tones[name.codeUnits.fold(0, (a, b) => a + b) % _tones.length];

/// Contenedor de página: en claro el vivo; en oscuro, papel (el tinte de color
/// no llega al papel) con borde de contenedor `lineSoft`.
Color _surface(BuildContext context, Color vivid) =>
    Theme.of(context).brightness == Brightness.dark
    ? context.slush.paper
    : vivid;

BoxDecoration _box(
  BuildContext context,
  Color color,
  double r, {
  bool shadow = false,
}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(r),
  border: Border.fromBorderSide(context.slush.borderSoft),
  boxShadow: shadow ? context.slush.shadows : null,
);

/// Cabecera «JAM» gigante con onda azul detrás y pegatina «EN VIVO». El
/// titular se encoge (nunca desborda) y no escala más de 1,3.
class _Hero extends StatelessWidget {
  const _Hero({this.live = true});
  final bool live;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < Breakpoints.compact;
      final size = compact ? 96.0 : 140.0;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: size * .14,
            child: SlushWave(height: size),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'JAM',
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.3),
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontSize: size, height: .95),
            ),
          ),
          // Menos pegatinas en pantallas estrechas: solo la onda.
          if (live && !compact)
            Positioned(
              left: size * 1.8,
              top: 0,
              child: const SlushSticker('EN VIVO', size: 84),
            ),
        ],
      );
    },
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, this.image);
  final String name;
  final Uint8List? image;
  static const size = 44.0;
  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _tone(name),
          shape: BoxShape.circle,
          border: Border.fromBorderSide(context.slush.border),
        ),
        child: image == null
            ? Text(
                initial,
                style: const TextStyle(
                  fontFamily: 'Bagel Fat One',
                  fontSize: 18,
                  color: Slush.ink,
                ),
              )
            : ClipOval(
                child: Image.memory(
                  image!,
                  width: size - 4,
                  height: size - 4,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      Text(initial, style: const TextStyle(color: Slush.ink)),
                ),
              ),
      ),
    );
  }
}

/// Entrada «pop» de la pegatina de confirmación: 280 ms, escala .9→1 y giro
/// ±.04. Solo la primera vez de la sesión; con movimiento reducido, sin
/// animación.
class _PopIn extends StatefulWidget {
  const _PopIn({required this.child});
  final Widget child;
  static bool _played = false;
  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> {
  late final bool _play;
  @override
  void initState() {
    super.initState();
    _play = !_PopIn._played;
    _PopIn._played = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_play || SlushMotion.reduce(context)) return widget.child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: SlushMotion.easeOut,
      child: widget.child,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.rotate(
          angle: -.04 * (1 - t),
          child: Transform.scale(scale: .9 + .1 * t, child: child),
        ),
      ),
    );
  }
}

/// Dos columnas desde 900 px, una columna debajo; margen y ancho máximo por
/// tokens.
class _Columns extends StatelessWidget {
  const _Columns({required this.left, required this.right});
  final Widget left, right;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      padding: EdgeInsets.all(SlushSpacing.margin(box.maxWidth)),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Breakpoints.isWide(box.maxWidth)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 11, child: left),
                    const SizedBox(width: SlushSpacing.s24),
                    Expanded(flex: 9, child: right),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    left,
                    const SizedBox(height: SlushSpacing.s24),
                    right,
                  ],
                ),
        ),
      ),
    ),
  );
}

String _mmss(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Jam con sesión activa, con la composición de Slush.
class SlushJamActive extends StatelessWidget {
  const SlushJamActive({super.key, required this.controller});
  final JamController controller;
  JamController get c => controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) =>
        _Columns(left: _left(context), right: _right(context)),
  );

  Widget _left(BuildContext context) {
    final s = c.service;
    final invite = s.invite;
    final remote = invite?.isRemote == true;
    final p = context.slush;
    final people = [
      for (final q in s.participants)
        if (q.connected) q,
    ];
    Future<void> copy(String text, String done) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(done));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Hero(live: s.connected),
        const SizedBox(height: SlushSpacing.s12),
        Wrap(
          spacing: SlushSpacing.s8,
          runSpacing: SlushSpacing.s8,
          children: [
            SlushPill(
              s.connected
                  ? (s.isRemote
                        ? '● EN VIVO · EN LÍNEA'
                        : '● EN VIVO · RED LOCAL')
                  : 'SIN CONEXIÓN',
              color: s.connected ? Slush.mint : Slush.orange,
            ),
            SlushPill(
              c.listeningTogether ? 'SINCRONIZADA' : 'SOLO AÑADIR',
              color: Slush.lilac,
            ),
            SlushPill('ANFITRIÓN: ${c.hostName}', color: Slush.yellow),
          ],
        ),
        const SizedBox(height: SlushSpacing.s24),
        if (invite != null)
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(SlushSpacing.s16),
                decoration: _box(
                  context,
                  Slush.violet,
                  SlushRadius.r24,
                  shadow: true,
                ),
                child: Wrap(
                  spacing: SlushSpacing.s16,
                  runSpacing: SlushSpacing.s12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    slushQrFrame(
                      context,
                      JamQrCode(data: invite.encode(), size: 160),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ESCANEA PARA UNIRTE',
                            style: TextStyle(
                              fontFamily: 'Bagel Fat One',
                              fontSize: 22,
                              height: 1.2,
                              color: Slush.onViolet,
                            ),
                          ),
                          const SizedBox(height: SlushSpacing.s4),
                          Text(
                            remote ? 'o ingresá el código' : 'red local',
                            style: const TextStyle(
                              color: Slush.onViolet,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: SlushSpacing.s8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              remote ? invite.code : invite.endpoint,
                              style: jamCodeStyle(
                                remote ? 32 : 24,
                                color: Slush.onViolet,
                                spacing: remote ? 3 : 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: SlushSpacing.s12),
                          OutlinedButton(
                            style: jamOnVioletButton(context),
                            onPressed: () => copy(
                              remote
                                  ? 'Únete a mi Jam en Aurora: ${invite.encode()} (código ${invite.code})'
                                  : invite.encode(),
                              'Enlace copiado. Compártelo solo con quien quieras.',
                            ),
                            child: const Text('COPIAR ENLACE'),
                          ),
                          JamInviteFriendButton(
                            jam: c,
                            style: jamOnVioletButton(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (s.connected)
                Positioned(
                  right: -6,
                  top: -20,
                  child: _PopIn(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Slush.mint,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(p.border),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 28,
                        color: Slush.ink,
                        semanticLabel: 'Conectado',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: SlushSpacing.s24),
        Text(
          '${c.peopleCount} ${c.peopleCount == 1 ? 'persona' : 'personas'} en la sala',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: SlushSpacing.s8),
        for (final (i, person) in people.indexed) ...[
          if (i > 0) const Divider(),
          _person(context, person),
        ],
        if (people.isNotEmpty) const Divider(),
        _invitePerson(context),
        if (!s.connected || c.error != null || c.bridge.warning != null) ...[
          const SizedBox(height: SlushSpacing.s12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SlushSpacing.s12),
            decoration: _box(context, Slush.yellow, SlushRadius.r16),
            child: Text(
              c.bridge.warning ??
                  c.error ??
                  'Sin conexión con la Jam. Pulsa reconectar.',
              style: const TextStyle(color: Slush.ink, fontSize: 14),
            ),
          ),
          if (!s.connected)
            TextButton(
              onPressed: c.busy ? null : c.reconnect,
              child: const Text('RECONECTAR'),
            ),
        ],
      ],
    );
  }

  /// Fila de participante: avatar 44, nombre en una línea y estado en píldora.
  Widget _person(BuildContext context, JamParticipant person) {
    final s = c.service;
    final me = person.id == s.participantId;
    final name = me ? '${person.name} (tú)' : person.name;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SlushSpacing.s8),
        child: Row(
          children: [
            _Avatar(person.name, c.avatarOf(person.id)),
            const SizedBox(width: SlushSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: name,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: SlushSpacing.s4),
                  Wrap(
                    spacing: SlushSpacing.s8,
                    runSpacing: SlushSpacing.s4,
                    children: [
                      SlushPill(
                        jamRoleLabel(person.role),
                        color: switch (person.role) {
                          JamRole.host => Slush.yellow,
                          JamRole.coHost => Slush.lilac,
                          JamRole.guest => Slush.mint,
                        },
                      ),
                      if (person.muted)
                        const SlushPill('Silenciado', color: Slush.orange),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _invitePerson(BuildContext context) {
    final s = c.service;
    final p = context.slush;
    return Tooltip(
      message: 'Invitar',
      child: InkWell(
        borderRadius: BorderRadius.circular(SlushRadius.r16),
        onTap: s.connected ? () => showJamInviteSheet(context, c) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Row(
            children: [
              Container(
                width: _Avatar.size,
                height: _Avatar.size,
                decoration: BoxDecoration(
                  color: p.paper,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    s.connected
                        ? p.border
                        : BorderSide(
                            color: p.disabledBorder,
                            width: SlushStroke.base,
                          ),
                  ),
                ),
                child: Icon(
                  Icons.add,
                  size: 22,
                  color: s.connected ? p.ink : p.disabledText,
                ),
              ),
              const SizedBox(width: SlushSpacing.s12),
              Expanded(
                child: Text(
                  'Invitar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: s.connected ? p.ink : p.disabledText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _right(BuildContext context) {
    final s = c.service;
    final p = context.slush;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _queue(context),
        const SizedBox(height: SlushSpacing.s24),
        _permissions(context),
        const SizedBox(height: SlushSpacing.s16),
        Wrap(
          spacing: SlushSpacing.s12,
          runSpacing: SlushSpacing.s8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: () => showJamPanel(context, c),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('AJUSTES DE LA JAM'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: p.ink,
                foregroundColor: p.paper,
              ),
              onPressed: c.busy ? null : () => _leave(context),
              icon: const Icon(Icons.close, size: 18),
              label: Text(s.isHost ? 'TERMINAR JAM' : 'SALIR DE LA JAM'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _leave(BuildContext context) async {
    final host = c.service.isHost;
    final ok =
        !host ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Terminar la Jam'),
                content: const Text(
                  'Se cerrará para todos. Si prefieres que siga, otra persona recibirá el mando.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Terminar'),
                  ),
                ],
              ),
            ) ==
            true;
    if (ok) await c.leave();
  }

  Widget _queue(BuildContext context) {
    final s = c.service;
    final p = context.slush;
    final accent = AccentScope.of(context, c.app.accentColor);
    final tint = HSLColor.fromColor(
      accent,
    ).withSaturation(.7).withLightness(.88).toColor();
    final playingId = s.playback?.entryId;
    return Container(
      padding: const EdgeInsets.all(SlushSpacing.s16),
      decoration: _box(context, _surface(context, tint), SlushRadius.r24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cola compartida',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: SlushSpacing.s8),
              FilledButton.icon(
                onPressed: c.canAdd ? () => showJamAddSheet(context, c) : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('AGREGAR'),
              ),
            ],
          ),
          const SizedBox(height: SlushSpacing.s12),
          if (s.queue.isEmpty)
            Padding(
              padding: const EdgeInsets.all(SlushSpacing.s8),
              child: Text(
                'La cola está vacía. Pulsa «Agregar» para buscar canciones'
                '${''} o deja que el autoplay añada música al grupo.',
                style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45),
              ),
            ),
          for (final (i, e) in s.queue.indexed)
            _row(context, i, e, e.id == playingId),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i, JamQueueEntry e, bool playing) {
    final s = c.service;
    final pending = e.status == JamEntryStatus.pending;
    final mine = e.up.contains(s.participantId);
    final who = s.participantName(e.suggestedFor ?? e.addedBy);
    final outer = context.slush;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Sobre amarillo el contenido va en tinta fija (también en oscuro), con
    // tema claro para iconos y botones.
    final Widget Function(BuildContext, Widget) wrap = playing
        ? slushOnVivid
        : (_, w) => w;
    return Padding(
      padding: const EdgeInsets.only(bottom: SlushSpacing.s8),
      child: Material(
        color: playing ? Slush.yellow : (dark ? outer.raised : outer.paper),
        shape: RoundedRectangleBorder(
          side: playing ? outer.border : outer.borderSoft,
          borderRadius: BorderRadius.circular(SlushRadius.r16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: s.isHost && !pending && s.connected ? () => c.play(e) : null,
          child: wrap(
            context,
            Builder(
              builder: (context) {
                final p = context.slush;
                final text = Theme.of(context).textTheme;
                return ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 60),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SlushSpacing.s12,
                      vertical: SlushSpacing.s8,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${i + 1}',
                              style: jamCodeStyle(12, color: p.ink2),
                            ),
                          ),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(SlushRadius.r8),
                          child: Artwork(
                            track: jamTrackAsTrack(e.track),
                            artworkContext: ArtworkContext.thumbnailCompact,
                            size: 40,
                            radius: SlushRadius.r8,
                          ),
                        ),
                        const SizedBox(width: SlushSpacing.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleSmall,
                              ),
                              Text(
                                pending
                                    ? '${e.track.artist} · espera aprobación'
                                    : e.track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.ink2, fontSize: 12),
                              ),
                              const SizedBox(height: SlushSpacing.s4),
                              Wrap(
                                spacing: SlushSpacing.s8,
                                runSpacing: SlushSpacing.s4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SlushPill(
                                    e.suggestedFor != null
                                        ? 'PARA $who'
                                        : 'AGREGÓ $who',
                                    color: _tone(who),
                                  ),
                                  if (e.track.durationMs > 0)
                                    Text(
                                      _mmss(e.track.durationMs),
                                      style: jamCodeStyle(12, color: p.ink2),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (pending && c.isStaff) ...[
                          IconButton(
                            tooltip: 'Aprobar',
                            constraints: const BoxConstraints.tightFor(
                              width: SlushControl.touch,
                              height: SlushControl.touch,
                            ),
                            onPressed: () => s.approve(e.id, accept: true),
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 22,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Rechazar',
                            constraints: const BoxConstraints.tightFor(
                              width: SlushControl.touch,
                              height: SlushControl.touch,
                            ),
                            onPressed: () => s.approve(e.id, accept: false),
                            icon: const Icon(Icons.cancel_outlined, size: 22),
                          ),
                        ] else ...[
                          InkResponse(
                            radius: SlushControl.touch / 2,
                            onTap: s.connected && s.rules.votes && !pending
                                ? () => s.vote(e.id, mine ? 0 : 1)
                                : null,
                            child: SizedBox(
                              width: SlushControl.touch,
                              height: SlushControl.touch,
                              child: Center(
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.fromBorderSide(p.border),
                                  ),
                                  child: Icon(
                                    mine
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 18,
                                    // Naranja solo sobre papel/raised: sobre el
                                    // amarillo no llega a 3:1.
                                    color: mine && !playing
                                        ? Slush.orange
                                        : p.ink,
                                    semanticLabel: 'Me gusta (${e.up.length})',
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (c.canRemove || e.addedBy == s.participantId)
                            IconButton(
                              tooltip: 'Quitar de la cola',
                              constraints: const BoxConstraints.tightFor(
                                width: SlushControl.touch,
                                height: SlushControl.touch,
                              ),
                              onPressed: s.connected ? () => c.remove(e) : null,
                              icon: const Icon(Icons.close, size: 20),
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _permissions(BuildContext context) {
    final s = c.service;
    final p = context.slush;
    final guests = s.participants.where((p) => p.role == JamRole.guest);
    bool all(bool Function(JamPermissions) f) => guests.isEmpty
        ? f(const JamPermissions())
        : guests.every((p) => f(p.permissions));
    void setAll(JamPermissions Function(JamPermissions) f) {
      for (final p in guests) {
        c.setPermissions(p.id, f(p.permissions));
      }
    }

    final host = s.isHost;
    Widget row(String label, bool value, ValueChanged<bool>? onChanged) =>
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SlushControl.touch),
          child: Row(
            children: [
              Switch(value: value, onChanged: host ? onChanged : null),
              const SizedBox(width: SlushSpacing.s12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.25,
                    color: p.ink,
                  ),
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(SlushSpacing.s16),
      decoration: _box(
        context,
        _surface(context, Slush.lilac),
        SlushRadius.r24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Permisos', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: SlushSpacing.s8),
          row(
            'Invitados agregan canciones',
            all((p) => p.add),
            (v) => setAll((p) => p.copyWith(add: v)),
          ),
          row(
            'Invitados pueden saltar',
            all((p) => p.skip),
            (v) => setAll((p) => p.copyWith(skip: v)),
          ),
          row(
            'Audio sincronizado en cada equipo',
            c.listeningTogether,
            c.busy
                ? null
                : (v) =>
                      c.setMode(v ? JamMode.synchronized : JamMode.queueOnly),
          ),
          if (!host)
            Padding(
              padding: const EdgeInsets.only(top: SlushSpacing.s8),
              child: Text(
                'Solo el anfitrión cambia los permisos.',
                style: TextStyle(fontSize: 12, color: p.ink2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Jam sin sesión: crear o unirse, con la misma composición.
class SlushJamIdle extends StatelessWidget {
  const SlushJamIdle({
    super.key,
    required this.name,
    required this.code,
    required this.busy,
    required this.message,
    required this.onStart,
    required this.onJoin,
    required this.onScan,
    required this.scanLabel,
  });
  final TextEditingController name, code;
  final bool busy;
  final String? message;
  final VoidCallback onStart, onJoin, onScan;
  final String scanLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final text = Theme.of(context).textTheme;
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Hero(live: false),
        const SizedBox(height: SlushSpacing.s12),
        const Wrap(
          spacing: SlushSpacing.s8,
          runSpacing: SlushSpacing.s8,
          children: [
            SlushPill('SIN SESIÓN', color: Slush.yellow),
            SlushPill('ESCUCHEN JUNTOS', color: Slush.lilac),
          ],
        ),
        const SizedBox(height: SlushSpacing.s16),
        if (busy) const LinearProgressIndicator(),
        if (message != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: SlushSpacing.s12),
            padding: const EdgeInsets.all(SlushSpacing.s12),
            decoration: _box(context, Slush.yellow, SlushRadius.r16),
            child: Text(
              message!,
              style: const TextStyle(color: Slush.ink, fontSize: 14),
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SlushSpacing.s16),
          decoration: _box(
            context,
            Slush.violet,
            SlushRadius.r24,
            shadow: true,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EMPIEZA UNA JAM',
                style: TextStyle(
                  fontFamily: 'Bagel Fat One',
                  fontSize: 24,
                  height: 1.2,
                  color: Slush.onViolet,
                ),
              ),
              const SizedBox(height: SlushSpacing.s4),
              const Text(
                'Se crea al instante y te mostramos el QR y el código para invitar.',
                style: TextStyle(
                  color: Slush.onViolet,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: SlushSpacing.s12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Slush.yellow,
                ).copyWith(side: jamOnVioletButton(context).side),
                onPressed: busy ? null : onStart,
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: const Text('INICIAR UNA JAM'),
              ),
            ],
          ),
        ),
      ],
    );
    final side = KeyedSubtree(
      key: const ValueKey('jam-idle-side'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SlushSpacing.s16),
            decoration: _box(
              context,
              _surface(context, Slush.lilac),
              SlushRadius.r24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unirme a una Jam', style: text.titleLarge),
                const SizedBox(height: SlushSpacing.s12),
                TextField(
                  controller: name,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    labelText: 'Tu nombre (opcional)',
                  ),
                ),
                TextField(
                  controller: code,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: busy ? null : (_) => onJoin(),
                  decoration: const InputDecoration(
                    labelText: 'Código o enlace de la Jam',
                    hintText: 'Por ejemplo K7M2QX',
                  ),
                ),
                const SizedBox(height: SlushSpacing.s12),
                Wrap(
                  spacing: SlushSpacing.s12,
                  runSpacing: SlushSpacing.s8,
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: p.ink,
                        foregroundColor: p.paper,
                      ),
                      onPressed: busy ? null : onJoin,
                      child: const Text('UNIRME CON CÓDIGO'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onScan,
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: Text(scanLabel.toUpperCase()),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: SlushSpacing.s16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SlushSpacing.s16),
            decoration: _box(
              context,
              _surface(context, Slush.lilac),
              SlushRadius.r24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cómo funciona', style: text.titleLarge),
                const SizedBox(height: SlushSpacing.s12),
                for (final step in const [
                  'Invitados agregan canciones',
                  'Audio sincronizado en cada equipo',
                  'Escanea el QR o usa el código',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: SlushSpacing.s8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle, color: p.ink, size: 20),
                        const SizedBox(width: SlushSpacing.s8),
                        Expanded(
                          child: Text(
                            step,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.35,
                              color: p.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: SlushSpacing.s16),
          Text(
            'Cada dispositivo usa sus propias fuentes de audio; los archivos locales no se envían.',
            style: TextStyle(fontSize: 12, height: 1.4, color: p.ink2),
          ),
        ],
      ),
    );
    return _Columns(left: main, right: side);
  }
}
