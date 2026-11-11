import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Int64List;

import 'package:aurora_music/bridge/api/lyrics_align.dart' as rust;
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_auto_sync.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = Track(id: 'yt:z', title: 'Canción', artist: 'Artista');
final _synced = LyricsResult(
  LyricsKind.synced,
  lines: [
    for (var i = 0; i < 5; i++)
      LyricLine(Duration(seconds: 2 + i * 5), 'linea numero $i de la letra'),
  ],
);
const _plain = LyricsResult(
  LyricsKind.plain,
  text: 'uno dos tres\ncuatro cinco seis\n\nsiete ocho nueve\ndiez once doce',
);
const _file = ResolvedAudio(input: 'C:/musica/cancion.mp3');

void main() {
  late Directory dir;
  late LyricsService service;
  late List<({List<rust.AlignLine> lines, int scan})> calls;
  var ready = true;
  var found = true;
  List<int> starts = [14000, 19000, 24000, 29000, 34000];
  int? shift = 12000;
  Object? failure;

  LyricsAutoSync create() => LyricsAutoSync(
    service,
    available: () => ready,
    modelPath: () => 'modelo.bin',
    align:
        ({
          required modelPath,
          required input,
          required headers,
          required lines,
          required scanSecs,
          language,
        }) async {
          calls.add((lines: lines, scan: scanSecs));
          if (failure != null) throw failure!;
          return rust.LyricsAlignment(
            found: found,
            startsMs: Int64List.fromList(found ? starts : const []),
            anchored: found ? 4 : 0,
            shiftMs: found ? shift : null,
          );
        },
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aurora_autosync_');
    service = LyricsService();
    calls = [];
    ready = true;
    found = true;
    starts = [14000, 19000, 24000, 29000, 34000];
    shift = 12000;
    failure = null;
  });
  tearDown(() {
    service.dispose();
    dir.deleteSync(recursive: true);
  });

  test('a synced lyric measured 12 s late is stored and applied', () async {
    expect(await create().run(_track, _synced, _file, dir), isTrue);
    final adjust = await service.readAdjust(_track, dir);
    expect(adjust?.source, 'audio');
    expect(adjust?.startsMs, starts);
    final shown = await service.adjusted(_track, dir, _synced);
    expect(shown.lines.first.at, const Duration(seconds: 14));
    // Con tiempos solo se analiza el principio de la canción.
    expect(calls.single.scan, LyricsAutoSync.scanSyncedSecs);
    expect(calls.single.lines.first.atMs, 2000);
  });

  test('a plain lyric gets a time per line and is analysed in full', () async {
    starts = [34000, 38000, 45000, 52000];
    expect(await create().run(_track, _plain, _file, dir), isTrue);
    // Las líneas vacías no cuentan: cuatro textos, cuatro horas.
    expect(calls.single.lines.map((l) => l.text), [
      'uno dos tres',
      'cuatro cinco seis',
      'siete ocho nueve',
      'diez once doce',
    ]);
    expect(calls.single.lines.every((l) => l.atMs == null), isTrue);
    expect(calls.single.scan, LyricsAutoSync.scanPlainSecs);
    final shown = await service.adjusted(_track, dir, _plain);
    expect(shown.kind, LyricsKind.synced);
    expect(shown.lines.map((l) => l.at.inSeconds), [34, 38, 45, 52]);
  });

  test(
    'it measures once per track, even when the result was nothing',
    () async {
      final sync = create();
      expect(await sync.run(_track, _synced, _file, dir), isTrue);
      expect(await sync.run(_track, _synced, _file, dir), isFalse);
      expect(calls, hasLength(1));

      const other = Track(id: 'yt:w', title: 'Otra', artist: 'Artista');
      found = false;
      expect(await sync.run(other, _synced, _file, dir), isFalse);
      expect(await sync.run(other, _synced, _file, dir), isFalse);
      expect(
        calls,
        hasLength(2),
        reason: 'el intento fallido tampoco se repite',
      );
      expect((await service.readAdjust(other, dir))?.tried, isTrue);
    },
  );

  test(
    'a failed measurement keeps the duration estimate and does not retry',
    () async {
      await service.writeAdjust(
        _track,
        dir,
        const LyricsAdjust(source: 'duration', shiftMs: 9000),
      );
      found = false;
      expect(await create().run(_track, _synced, _file, dir), isFalse);
      final adjust = await service.readAdjust(_track, dir);
      expect(adjust?.shiftMs, 9000);
      expect(adjust?.source, 'duration');
      expect(adjust?.settled, isTrue);
    },
  );

  test('a measured shift replaces the duration estimate', () async {
    await service.writeAdjust(
      _track,
      dir,
      const LyricsAdjust(source: 'duration', shiftMs: 9000),
    );
    expect(await create().run(_track, _synced, _file, dir), isTrue);
    final shown = await service.adjusted(_track, dir, _synced);
    expect(shown.lines.first.at, const Duration(seconds: 14));
  });

  test('a lyric that already matches the audio changes nothing', () async {
    shift = 150;
    starts = [for (final l in _synced.lines) l.at.inMilliseconds + 150];
    expect(await create().run(_track, _synced, _file, dir), isFalse);
    final adjust = await service.readAdjust(_track, dir);
    expect(adjust?.settled, isTrue);
    expect(adjust?.startsMs, isNull);
    expect(
      (await service.adjusted(_track, dir, _synced)).lines.first.at,
      const Duration(seconds: 2),
    );
  });

  test(
    'nothing runs without audio, model, enough lines or a usable lyric',
    () async {
      final sync = create();
      expect(await sync.run(_track, _synced, null, dir), isFalse);
      expect(
        await sync.run(
          _track,
          const LyricsResult(LyricsKind.notFound),
          _file,
          dir,
        ),
        isFalse,
      );
      expect(
        await sync.run(
          _track,
          const LyricsResult(LyricsKind.plain, text: 'solo\ndos'),
          _file,
          dir,
        ),
        isFalse,
      );
      ready = false;
      expect(await sync.run(_track, _synced, _file, dir), isFalse);
      expect(calls, isEmpty);
    },
  );

  test('errors leave the lyrics as they were and can be retried', () async {
    failure = StateError('sin modelo');
    final sync = create();
    expect(await sync.run(_track, _synced, _file, dir), isFalse);
    expect(await service.readAdjust(_track, dir), isNull);
    failure = null;
    expect(await sync.run(_track, _synced, _file, dir), isTrue);
  });
}
