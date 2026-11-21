import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/jam/jam_service.dart';
import 'package:aurora_music/jam/jam_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_jam_backend.dart';
import 'support/fakes.dart';

Track song(int n, {String artist = 'Artist'}) {
  final id = 'sync${n.toString().padLeft(7, '0')}';
  return Track(
    id: 'yt:$id',
    title: 'Song $n',
    artist: '$artist $n',
    pageUrl: 'https://music.youtube.com/watch?v=$id',
    duration: const Duration(minutes: 3),
  );
}

class Peer {
  Peer(this.audio, this.app, this.jam);
  final FakeAudio audio;
  final AppController app;
  final JamController jam;
}

Future<Peer> peer(
  FakeJamBackend backend, {
  List<Track> library = const [],
  JamSuggestionAdapter Function()? adapter,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final audio = FakeAudio();
  final app = await createTestController(tracks: library, audio: audio);
  final jam = JamController(
    app: app,
    transport: backend.transport(),
    suggestionAdapter: adapter,
    topUpTimeout: timeout,
  );
  addTearDown(() async {
    jam.dispose();
    await closeTestController(app);
  });
  return Peer(audio, app, jam);
}

Future<void> eventually(bool Function() ok, [String? what]) async {
  for (var i = 0; i < 300; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TestFailure('timeout: ${what ?? ''}');
}

String? input(Peer p) => p.audio.loaded?.input;

void main() {
  final library = [for (var i = 0; i < 12; i++) song(i)];

  test(
    'la Jam empieza en silencio y, al añadir, los 3 suenan igual y sincronizados',
    () async {
      final backend = FakeJamBackend();
      final host = await peer(backend, library: library);
      await host.app.playTrack(library[0], context: library);
      await host.jam.hostOnline('Ana');
      // Lo que sonaba se pausa y la cola queda vacía: nada se añade solo.
      expect(host.audio.isPlaying, isFalse);
      expect(host.jam.service.upcomingQueued, 0);
      expect(host.jam.autoplayEnabled, isFalse);
      final code = host.jam.service.invite!.code;
      final g1 = await peer(backend);
      final g2 = await peer(backend);
      await g1.jam.join(code, 'Beto');
      await g2.jam.join(code, 'Cris');
      // Las sugerencias del grupo se ven, pero no pasan a la cola solas.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(host.jam.service.upcomingQueued, 0);
      expect([host, g1, g2].every((p) => !p.audio.isPlaying), isTrue);

      host.jam.add(library[0]);
      await eventually(
        () =>
            [host, g1, g2].every((p) => input(p) != null && p.audio.isPlaying),
        'los tres suenan',
      );
      expect(
        host.jam.service.queue
            .firstWhere((e) => e.status == JamEntryStatus.queued)
            .track
            .title,
        'Song 0',
      );
      expect(host.jam.service.mode, JamMode.synchronized);
      final want = 'https://example.test/${library[0].id}';
      for (final p in [host, g1, g2]) {
        expect(input(p), want);
        expect(p.audio.position.inMilliseconds.abs(), lessThan(1000));
      }
    },
  );

  test(
    'cola vacía: al añadir una pista empieza sola, sin Reproducir',
    () async {
      final backend = FakeJamBackend();
      final host = await peer(backend);
      await host.jam.hostOnline('Ana');
      final g1 = await peer(backend);
      await g1.jam.join(host.jam.service.invite!.code, 'Beto');
      expect(host.audio.loaded, isNull);

      host.jam.add(song(7));
      await eventually(
        () => input(host) != null && input(g1) != null && g1.audio.isPlaying,
      );
      expect(input(g1), 'https://example.test/${song(7).id}');
    },
  );

  test('al agotarse una pista empieza la siguiente para todos', () async {
    final backend = FakeJamBackend();
    final host = await peer(backend);
    await host.jam.hostOnline('Ana');
    final g1 = await peer(backend);
    await g1.jam.join(host.jam.service.invite!.code, 'Beto');
    host.jam.addTracks([song(1), song(2)]);
    await eventually(() => input(g1) == 'https://example.test/${song(1).id}');
    host.audio.completions.add(null);
    await eventually(
      () =>
          input(host) == 'https://example.test/${song(2).id}' &&
          input(g1) == 'https://example.test/${song(2).id}',
    );
  });

  for (final kind in ['vacío', 'error', 'lento']) {
    test(
      'la cola nunca baja de ${JamController.minAhead} con motor $kind',
      () async {
        final backend = FakeJamBackend();
        final host = await peer(
          backend,
          library: library,
          timeout: const Duration(milliseconds: 100),
          adapter: () => JamSuggestionAdapter(
            related: (_) async {
              if (kind == 'error') throw StateError('sin red');
              if (kind == 'lento') {
                await Future<void>.delayed(const Duration(seconds: 3));
              }
              return const [];
            },
            seeds: () => [library[0]],
            local: () => const [],
          ),
        );
        await host.jam.hostOnline('Ana');
        await host.jam.setAutoplay(true);
        host.jam.add(song(100));
        await eventually(() => input(host) != null);
        final service = host.jam.service;
        await eventually(
          () => service.upcomingQueued >= JamController.minAhead,
          'relleno inicial',
        );
        for (var i = 0; i < 8; i++) {
          host.audio.completions.add(null);
          await eventually(
            () =>
                service.upcomingQueued >= JamController.minAhead &&
                !host.jam.busy,
            'relleno tras pista $i',
          );
          expect(service.playback?.entryId, isNotNull);
        }
      },
    );
  }

  test('último recurso: repite favoritos aunque ya hayan sonado', () async {
    final backend = FakeJamBackend();
    final small = [for (var i = 0; i < 6; i++) song(i)];
    final host = await peer(backend, library: small);
    await host.app.toggleFavorite(small[0]);
    await host.jam.hostOnline('Ana');
    await host.jam.setAutoplay(true);
    host.jam.addTracks(small);
    await eventually(() => input(host) != null);
    for (var i = 0; i < 12; i++) {
      host.audio.completions.add(null);
      await eventually(
        () => host.jam.service.upcomingQueued >= small.length - 1,
      );
    }
    expect(host.jam.service.queue.length, lessThanOrEqualTo(200));
  });

  test(
    'cambio de modo en caliente y modos distintos entre invitados',
    () async {
      final backend = FakeJamBackend();
      final host = await peer(backend, library: library);
      await host.jam.hostOnline('Ana');
      final code = host.jam.service.invite!.code;
      final g1 = await peer(backend);
      final g2 = await peer(backend);
      await g1.jam.join(code, 'Beto');
      await g2.jam.join(code, 'Cris');
      host.jam.add(library[0]);
      await eventually(() => g1.audio.isPlaying && g2.audio.isPlaying);

      // Cris elige solo añadir: no reproduce, pero puede añadir.
      await g2.jam.setListening(false);
      await eventually(() => !g2.jam.bridge.enabled);
      expect(g1.jam.bridge.enabled, isTrue);
      g2.jam.add(song(50));
      await eventually(
        () => host.jam.service.queue.any((e) => e.track.title == 'Song 50'),
      );

      // El anfitrión pasa a «Solo añadir»: nadie reproduce.
      await host.jam.setMode(JamMode.queueOnly);
      await eventually(
        () => !host.jam.bridge.enabled && !g1.jam.bridge.enabled,
      );
      // Vuelve a «Escuchando»: retoma la misma pista en la posición actual.
      host.audio.position = const Duration(seconds: 30);
      await host.jam.setMode(JamMode.synchronized);
      await eventually(
        () =>
            host.jam.bridge.enabled &&
            g1.jam.bridge.enabled &&
            g1.audio.isPlaying,
      );
      expect(g2.jam.bridge.enabled, isFalse); // sigue en solo añadir
      expect(input(g1), 'https://example.test/${library[0].id}');
    },
  );

  test('si el anfitrión se cae, el invitado sigue sonando', () async {
    final backend = FakeJamBackend();
    final host = await peer(backend, library: library);
    await host.jam.hostOnline('Ana');
    final g1 = await peer(backend);
    await g1.jam.join(host.jam.service.invite!.code, 'Beto');
    host.jam.add(library[0]);
    await eventually(() => g1.audio.isPlaying);
    await g1.jam.service.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(g1.jam.bridge.enabled, isTrue);
    expect(g1.audio.isPlaying, isTrue);
  });
}
