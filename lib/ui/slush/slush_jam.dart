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

BoxDecoration _box(
  BuildContext context,
  Color color,
  double r, {
  bool shadow = false,
}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(r),
  border: Border.all(color: context.slush.line, width: 2),
  boxShadow: shadow ? context.slush.shadows : null,
);

/// Cabecera «JAM» gigante con onda azul detrás y pegatina «EN VIVO».
class _Hero extends StatelessWidget {
  const _Hero({this.live = true});
  final bool live;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 150,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned(left: 0, right: 0, top: 20, child: SlushWave()),
        Text(
          'JAM',
          style: Theme.of(
            context,
          ).textTheme.displayLarge?.copyWith(fontSize: 140, height: .95),
        ),
        if (live)
          const Positioned(
            left: 250,
            top: 0,
            child: SlushSticker('EN VIVO', size: 84),
          ),
      ],
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, this.image);
  final String name;
  final Uint8List? image;
  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _tone(name),
          shape: BoxShape.circle,
          border: Border.all(color: context.slush.line, width: 2),
        ),
        child: image == null
            ? Text(
                initial,
                style: const TextStyle(
                  fontFamily: 'Bagel Fat One',
                  fontSize: 17,
                  color: Slush.ink,
                ),
              )
            : ClipOval(
                child: Image.memory(
                  image!,
                  width: 36,
                  height: 36,
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
    builder: (context, _) {
      final left = _left(context);
      final right = _right(context);
      return LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: box.maxWidth >= 860
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 11, child: left),
                    const SizedBox(width: 24),
                    Expanded(flex: 9, child: right),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [left, const SizedBox(height: 24), right],
                ),
        ),
      );
    },
  );

  Widget _left(BuildContext context) {
    final s = c.service;
    final invite = s.invite;
    final remote = invite?.isRemote == true;
    final people = [
      for (final p in s.participants)
        if (p.connected) p,
    ];
    Future<void> copy(String text, String done) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(done)));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Hero(live: s.connected),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
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
        const SizedBox(height: 16),
        if (invite != null)
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: _box(context, Slush.violet, 22),
                child: slushOnVivid(
                  context,
                  Wrap(
                    spacing: 18,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        // QR siempre sobre blanco para que se pueda escanear.
                        decoration: _box(
                          context,
                          Colors.white,
                          10,
                        ), // sobre color vivo
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: JamQrCode(data: invite.encode(), size: 150),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ESCANEA PARA UNIRTE',
                              style: TextStyle(
                                fontFamily: 'Bagel Fat One',
                                fontSize: 20,
                                color: Colors.white, // sobre color vivo
                              ),
                            ),
                            Text(
                              remote ? 'o ingresá el código' : 'red local',
                              style: const TextStyle(
                                color: Colors.white, // sobre color vivo
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                remote ? invite.code : invite.endpoint,
                                style: const TextStyle(
                                  fontFamily: 'Bagel Fat One',
                                  fontSize: 40,
                                  letterSpacing: 2,
                                  color: Colors.white, // sobre color vivo
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () => copy(
                                remote
                                    ? 'Únete a mi Jam en Aurora: ${invite.encode()} (código ${invite.code})'
                                    : invite.encode(),
                                'Enlace copiado. Compártelo solo con quien quieras.',
                              ),
                              child: const Text('COPIAR ENLACE'),
                            ),
                            JamInviteFriendButton(jam: c),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (s.connected)
                Positioned(
                  right: -10,
                  top: -22,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Slush.mint,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.slush.line, width: 2.5),
                    ),
                    child: const Icon(Icons.check, size: 30, color: Slush.ink),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 18),
        Text(
          '${c.peopleCount} ${c.peopleCount == 1 ? 'persona' : 'personas'} en la sala',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in people)
              Tooltip(
                message: p.id == s.participantId ? '${p.name} (tú)' : p.name,
                child: _Avatar(p.name, c.avatarOf(p.id)),
              ),
            Tooltip(
              message: 'Invitar',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: s.connected
                    ? () => showJamInviteSheet(context, c)
                    : null,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.slush.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.slush.line, width: 2),
                  ),
                  child: const Icon(Icons.add, size: 20),
                ),
              ),
            ),
          ],
        ),
        if (!s.connected || c.error != null || c.bridge.warning != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: _box(context, Slush.yellow, 14),
            child: Text(
              c.bridge.warning ??
                  c.error ??
                  'Sin conexión con la Jam. Pulsa reconectar.',
              style: const TextStyle(color: Slush.ink),
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

  Widget _right(BuildContext context) {
    final s = c.service;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _queue(context),
        const SizedBox(height: 18),
        _permissions(context),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: () => showJamPanel(context, c),
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('AJUSTES DE LA JAM'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: context.slush.ink,
                foregroundColor: context.slush.paper,
              ),
              onPressed: c.busy ? null : () => _leave(context),
              icon: const Icon(Icons.close, size: 16),
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
    final accent = AccentScope.of(context, c.app.accentColor);
    final tint = HSLColor.fromColor(
      accent,
    ).withSaturation(.7).withLightness(.88).toColor();
    final playingId = s.playback?.entryId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(context, tint, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Cola compartida',
                  style: TextStyle(
                    fontFamily: 'Bagel Fat One',
                    fontSize: 22,
                    color: Slush.ink,
                  ),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: context.slush.ink,
                  foregroundColor: context.slush.paper,
                  minimumSize: const Size(0, 38),
                ),
                onPressed: c.canAdd ? () => showJamAddSheet(context, c) : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('AGREGAR'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (s.queue.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'La cola está vacía. Pulsa «Agregar» para buscar canciones'
                '${''} o deja que el autoplay añada música al grupo.',
                style: TextStyle(color: Slush.ink),
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
    // Sobre amarillo el contenido va en tinta fija (también en oscuro), con
    // tema claro para iconos y botones.
    final Widget Function(BuildContext, Widget) wrap = playing
        ? slushOnVivid
        : (_, w) => w;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: playing ? Slush.yellow : context.slush.paper,
        shape: RoundedRectangleBorder(
          side: context.slush.border,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: s.isHost && !pending && s.connected ? () => c.play(e) : null,
          child: wrap(
            context,
            Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Artwork(
                        track: jamTrackAsTrack(e.track),
                        artworkContext: ArtworkContext.thumbnailCompact,
                        size: 36,
                        radius: 8,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                          Text(
                            pending
                                ? '${e.track.artist} · espera aprobación'
                                : e.track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: SlushPill(
                        e.suggestedFor != null ? 'PARA $who' : 'AGREGÓ $who',
                        color: _tone(who),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (e.track.durationMs > 0)
                      Text(
                        _mmss(e.track.durationMs),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (pending && c.isStaff) ...[
                      IconButton(
                        tooltip: 'Aprobar',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => s.approve(e.id, accept: true),
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Rechazar',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => s.approve(e.id, accept: false),
                        icon: const Icon(Icons.cancel_outlined, size: 20),
                      ),
                    ] else ...[
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.slush.line,
                            width: 2,
                          ),
                        ),
                        child: InkResponse(
                          onTap: s.connected && s.rules.votes && !pending
                              ? () => s.vote(e.id, mine ? 0 : 1)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Icon(
                              mine ? Icons.favorite : Icons.favorite_border,
                              size: 16,
                              color: mine
                                  ? Slush.orange
                                  : (playing ? Slush.ink : context.slush.ink),
                              semanticLabel: 'Me gusta (${e.up.length})',
                            ),
                          ),
                        ),
                      ),
                      if (c.canRemove || e.addedBy == s.participantId)
                        IconButton(
                          tooltip: 'Quitar de la cola',
                          visualDensity: VisualDensity.compact,
                          onPressed: s.connected ? () => c.remove(e) : null,
                          icon: const Icon(Icons.close, size: 16),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _permissions(BuildContext context) {
    final s = c.service;
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Switch(value: value, onChanged: host ? onChanged : null),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: Slush.ink,
                  ),
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(context, Slush.lilac, 22),
      child: slushOnVivid(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Permisos',
              style: TextStyle(
                fontFamily: 'Bagel Fat One',
                fontSize: 22,
                color: Slush.ink,
              ),
            ),
            const SizedBox(height: 6),
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
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Solo el anfitrión cambia los permisos.',
                  style: TextStyle(fontSize: 11, color: Slush.ink),
                ),
              ),
          ],
        ),
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
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Hero(live: false),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            SlushPill('SIN SESIÓN', color: Slush.yellow),
            SlushPill('ESCUCHEN JUNTOS', color: Slush.lilac),
          ],
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (message != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: _box(context, Slush.yellow, 14),
            child: Text(message!, style: const TextStyle(color: Slush.ink)),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: _box(context, Slush.violet, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EMPIEZA UNA JAM',
                style: TextStyle(
                  fontFamily: 'Bagel Fat One',
                  fontSize: 24,
                  color: Colors.white, // sobre color vivo
                ),
              ),
              const Text(
                'Se crea al instante y te mostramos el QR y el código para invitar.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ), // sobre color vivo
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Slush.yellow),
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
            padding: const EdgeInsets.all(18),
            decoration: _box(context, Slush.lilac, 22),
            child: slushOnVivid(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Unirme a una Jam',
                    style: TextStyle(
                      fontFamily: 'Bagel Fat One',
                      fontSize: 22,
                      color: Slush.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Slush.ink,
                          foregroundColor: Colors.white, // sobre color vivo
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
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: _box(context, Slush.lilac, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cómo funciona',
                  style: TextStyle(
                    fontFamily: 'Bagel Fat One',
                    fontSize: 22,
                    color: Slush.ink,
                  ),
                ),
                const SizedBox(height: 10),
                for (final step in const [
                  'Invitados agregan canciones',
                  'Audio sincronizado en cada equipo',
                  'Escanea el QR o usa el código',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Slush.ink,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            step,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Slush.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Cada dispositivo usa sus propias fuentes de audio; los archivos locales no se envían.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 900
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 11, child: main),
                  const SizedBox(width: 24),
                  Expanded(flex: 9, child: side),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [main, const SizedBox(height: 18), side],
              ),
      ),
    );
  }
}
