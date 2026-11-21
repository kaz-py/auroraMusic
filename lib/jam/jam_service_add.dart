part of 'jam_service.dart';

/// Resultado de [JamServiceAdd.addMany].
class JamAddResult {
  const JamAddResult({
    required this.added,
    required this.dropped,
    required this.message,
    this.firstEntryId,
  });
  final int added, dropped;
  final String message;

  /// Primera entrada insertada (solo anfitrión); sirve para «Reproducir ahora».
  final String? firstEntryId;
}

/// Tope de la cola compartida (igual que el servidor).
const jamQueueLimit = 200;

/// Pistas por lote y espera entre lotes. El servidor admite 20 `add` por
/// minuto por invitado (LAN: 10 cada 5 s), así que se deja margen.
const jamRemoteBatch = 5;
const jamRemoteBatchWait = Duration(milliseconds: 15500);
const jamLanBatch = 8;
const jamLanBatchWait = Duration(milliseconds: 5200);

extension JamServiceAdd on JamService {
  /// Sugerencias del grupo, ya intercaladas (una por pista «A continuación»).
  List<GroupSuggestion> get groupSuggestions => [
    for (final e in queue)
      if (e.status == JamEntryStatus.suggested && e.id != playback?.entryId)
        GroupSuggestion(
          entryId: e.id,
          track: e.track,
          forId: e.suggestedFor ?? e.addedBy,
          forName: participantName(e.suggestedFor ?? e.addedBy),
          reason:
              'Sugerida para ${participantName(e.suggestedFor ?? e.addedBy)}',
        ),
  ];

  /// Cola que se muestra: lo que añadió la gente. Sin autoplay las sugerencias
  /// automáticas nunca suenan, así que solo salen en «Recomendado».
  List<JamQueueEntry> get visibleQueue => [
    for (final e in queue)
      if (rules.autoplay ||
          e.suggestedFor == null ||
          e.status == JamEntryStatus.queued)
        e,
  ];

  int get _currentIndex => queue.indexWhere((e) => e.id == playback?.entryId);

  /// Pistas en cola normal (no sugeridas) que faltan por sonar.
  int get upcomingQueued => [
    for (var i = _currentIndex + 1; i < queue.length; i++)
      if (queue[i].status == JamEntryStatus.queued) queue[i],
  ].length;

  /// Autoplay: sube a la cola normal las mejores sugerencias (ya intercaladas
  /// por participante, sin duplicados ni artista seguido) hasta tener
  /// [target] pistas por delante. Solo anfitrión; respeta la aprobación porque
  /// las pendientes no se tocan. Devuelve cuántas subió.
  int promoteSuggested({int target = kQueueLookahead}) {
    if (!isHost) return 0;
    final need = target - upcomingQueued;
    if (need <= 0) return 0;
    var done = 0;
    final copy = [...queue];
    for (var i = _currentIndex + 1; i < copy.length && done < need; i++) {
      if (copy[i].status != JamEntryStatus.suggested) continue;
      copy[i] = copy[i].copyWith(status: JamEntryStatus.queued);
      done++;
    }
    if (done > 0) {
      queue = copy;
      _changed();
    }
    return done;
  }

  /// Autoplay del anfitrión: añade al final hasta [need] pistas en cola normal.
  /// Con [repeat] admite pistas que ya sonaron (último recurso para no quedar
  /// en silencio). Si la cola está llena, descarta las ya sonadas más antiguas.
  int addAutoplay(
    List<JamTrack> tracks, {
    int need = kQueueLookahead,
    bool repeat = false,
  }) {
    if (!isHost || need <= 0) return 0;
    final cur = _currentIndex;
    final blocked = <String>{
      for (var i = 0; i < queue.length; i++)
        if (!repeat || i >= cur) ...queue[i].track.keys,
    };
    final fresh = <JamQueueEntry>[];
    for (final t in tracks) {
      if (fresh.length >= need) break;
      if (t.keys.any(blocked.contains)) continue;
      blocked.addAll(t.keys);
      fresh.add(
        JamQueueEntry(
          id: jamRandomSecret(12),
          track: t,
          addedBy: 'host',
          suggestedFor: 'host',
        ),
      );
    }
    if (fresh.isEmpty) return 0;
    final base = [...queue];
    final over = base.length + fresh.length - jamQueueLimit;
    if (over > 0) base.removeRange(0, min(over, max(cur, 0)));
    final room = jamQueueLimit - base.length;
    if (room <= 0) return 0;
    queue = [...base, ...fresh.take(room)];
    _changed();
    return min(room, fresh.length);
  }

  /// Inserta como anfitrión sin pasar por el límite de ritmo de invitados.
  List<JamQueueEntry> _hostInsert(List<JamTrack> tracks, int at) {
    final seen = <String>{for (final e in queue) ...e.track.keys};
    final fresh = <JamQueueEntry>[];
    for (final t in tracks) {
      if (queue.length + fresh.length >= jamQueueLimit) break;
      if (t.keys.any(seen.contains)) continue;
      seen.addAll(t.keys);
      fresh.add(
        JamQueueEntry(id: jamRandomSecret(12), track: t, addedBy: 'host'),
      );
    }
    if (fresh.isEmpty) return fresh;
    final copy = [...queue]..insertAll(at.clamp(0, queue.length), fresh);
    queue = copy;
    _changed();
    return fresh;
  }

  /// Añade varias pistas respetando límites. Anfitrión: inserción directa.
  /// Invitados: por lotes con espera (límite del servidor), avisando el avance
  /// por [onProgress]. [cancelled] corta entre lotes.
  Future<JamAddResult> addMany(
    List<JamTrack> input, {
    JamAddMode mode = JamAddMode.end,
    void Function(JamAddProgress)? onProgress,
    Future<void> Function(Duration)? wait,
    bool Function()? cancelled,
    Random? random,
  }) async {
    final me = this.me;
    if (!connected || me == null) {
      throw const JamException('Únete a una Jam para añadir canciones.');
    }
    if (me.muted) throw const JamException('El anfitrión te silenció.');
    if (!me.permissions.add && !isHost) {
      throw const JamException('El anfitrión no permite añadir canciones.');
    }
    final notes = <String>[];
    final seen = <String>{for (final e in queue) ...e.track.keys};
    var tracks = <JamTrack>[];
    var repeated = 0;
    for (final t in input) {
      if (t.keys.any(seen.contains)) {
        repeated++;
      } else {
        seen.addAll(t.keys);
        tracks.add(t);
      }
    }
    if (repeated > 0) notes.add('$repeated ya estaban en la cola o repetidas');
    var cap = jamQueueLimit - queue.length;
    var capName = 'la cola compartida admite $jamQueueLimit canciones';
    if (!me.isStaff) {
      final own = queue.where((e) => e.addedBy == me.id).length;
      final mine = rules.maxPerGuest - own;
      if (mine < cap) {
        cap = mine;
        capName = 'el tope por invitado es ${rules.maxPerGuest}';
      }
    }
    cap = cap.clamp(0, 1 << 30);
    var over = 0;
    if (tracks.length > cap) {
      over = tracks.length - cap;
      tracks = tracks.sublist(0, cap);
      notes.add('$over descartadas: $capName');
    }
    if (mode == JamAddMode.shuffle) tracks.shuffle(random);
    var effective = mode;
    if (!isHost &&
        (mode == JamAddMode.playNext || mode == JamAddMode.playNow)) {
      effective = JamAddMode.end;
      notes.add('solo el anfitrión puede cambiar el orden: van al final');
    }
    final dropped = repeated + over;
    String summary(int added) {
      final head = added == 1
          ? '1 canción añadida'
          : '$added canciones añadidas';
      return notes.isEmpty ? head : '$head (${notes.join('; ')})';
    }

    if (tracks.isEmpty) {
      final r = JamAddResult(added: 0, dropped: dropped, message: summary(0));
      onProgress?.call(JamAddProgress(dropped: dropped, message: r.message));
      return r;
    }
    if (isHost) {
      final at = effective == JamAddMode.end ? queue.length : _currentIndex + 1;
      final fresh = _hostInsert(tracks, at);
      final r = JamAddResult(
        added: fresh.length,
        dropped: dropped + tracks.length - fresh.length,
        message: summary(fresh.length),
        firstEntryId: fresh.firstOrNull?.id,
      );
      onProgress?.call(
        JamAddProgress(
          done: fresh.length,
          total: fresh.length,
          dropped: r.dropped,
          message: r.message,
        ),
      );
      return r;
    }
    final size = isRemote ? jamRemoteBatch : jamLanBatch;
    final pause = isRemote ? jamRemoteBatchWait : jamLanBatchWait;
    final sleep = wait ?? Future<void>.delayed;
    var sent = 0;
    for (var i = 0; i < tracks.length; i += size) {
      if (cancelled?.call() == true || !connected) {
        notes.add('interrumpido');
        break;
      }
      onProgress?.call(
        JamAddProgress(
          done: sent,
          total: tracks.length,
          running: true,
          dropped: dropped,
          message: 'Añadiendo $sent de ${tracks.length}…',
        ),
      );
      for (final t in tracks.skip(i).take(size)) {
        try {
          addTrack(t);
          sent++;
        } on JamException catch (failure) {
          notes.add(failure.message);
          i = tracks.length;
          break;
        }
      }
      if (i + size < tracks.length) await sleep(pause);
    }
    final r = JamAddResult(
      added: sent,
      dropped: dropped + tracks.length - sent,
      message: summary(sent),
    );
    onProgress?.call(
      JamAddProgress(
        done: sent,
        total: tracks.length,
        dropped: r.dropped,
        message: r.message,
      ),
    );
    return r;
  }
}
