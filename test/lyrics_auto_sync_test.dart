import 'dart:io';

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
const _file = ResolvedAudio(input: 'C:/musica/cancion.mp3');

void main() {
  late Directory dir;
  late LyricsService service;
  late List<List<rust.AlignLine>> calls;
  var ready = true;
  rust.LyricsAlignment result = const rust.LyricsAlignment(
    found: true,
    shiftMs: 12000,
    anchors: 3,
  );
  Object? failure;

  LyricsAutoSync create() => LyricsAutoSync(
    service,
    available: () => ready,
    libraryPath: () => 'libvosk.fake',
    modelPath: () => 'modelo',
    align:
        ({
          required libPath,
          required modelDir,
          required input,
          required headers,
          required lines,
        }) async {
          calls.add(lines);
          if (failure != null) throw failure!;
          return result;
        },
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aurora_autosync_');
    service = LyricsService();
    calls = [];
    ready = true;
    failure = null;
    result = const rust.LyricsAlignment(
      found: true,
      shiftMs: 12000,
      anchors: 3,
    );
  });
  tearDown(() {
    service.dispose();
    dir.deleteSync(recursive: true);
  });

  test(
    'a song that starts 12 s after its lyrics gets the lyrics delayed',
    () async {
      final offset = await create().run(_track, _synced, _file, dir);
      expect(offset, -12000);
      expect(await service.readOffset(_track, dir), -12000);
      expect((await service.readAutoOffset(_track, dir))?.source, 'audio');
      expect(calls.single, hasLength(5));
      expect(calls.single.first.atMs, 2000);
    },
  );

  test(
    'it measures once per track, even when the result was nothing',
    () async {
      final sync = create();
      expect(await sync.run(_track, _synced, _file, dir), isNotNull);
      expect(await sync.run(_track, _synced, _file, dir), isNull);
      expect(calls, hasLength(1));

      const other = Track(id: 'yt:w', title: 'Otra', artist: 'Artista');
      result = const rust.LyricsAlignment(found: false, shiftMs: 0, anchors: 0);
      expect(await sync.run(other, _synced, _file, dir), isNull);
      expect(await sync.run(other, _synced, _file, dir), isNull);
      expect(
        calls,
        hasLength(2),
        reason: 'el intento fallido tampoco se repite',
      );
      expect((await service.readAutoOffset(other, dir))?.source, 'tried');
    },
  );

  test('a failed measurement keeps the duration estimate', () async {
    await service.writeAutoOffset(_track, dir, -9000, 'duration');
    result = const rust.LyricsAlignment(found: false, shiftMs: 0, anchors: 0);
    expect(await create().run(_track, _synced, _file, dir), isNull);
    expect(await service.readOffset(_track, dir), -9000);
  });

  test('a measured shift replaces the duration estimate', () async {
    await service.writeAutoOffset(_track, dir, -9000, 'duration');
    final offset = await create().run(_track, _synced, _file, dir);
    expect(offset, -12000);
    expect(await service.readOffset(_track, dir), -12000);
  });

  test('a user adjustment is never touched', () async {
    await service.writeOffset(_track, dir, 700);
    expect(await create().run(_track, _synced, _file, dir), isNull);
    expect(calls, isEmpty);
    expect(await service.readOffset(_track, dir), 700);
  });

  test('tiny shifts are measurement noise and count as zero', () async {
    result = const rust.LyricsAlignment(found: true, shiftMs: 250, anchors: 4);
    await service.writeAutoOffset(_track, dir, -9000, 'duration');
    expect(await create().run(_track, _synced, _file, dir), 0);
    expect(await service.readOffset(_track, dir), 0);
  });

  test(
    'nothing runs without synced lyrics, local audio, model or library',
    () async {
      final sync = create();
      const plain = LyricsResult(LyricsKind.plain, text: 'a\nb');
      expect(await sync.run(_track, plain, _file, dir), isNull);
      expect(await sync.run(_track, _synced, null, dir), isNull);
      expect(
        await sync.run(
          _track,
          _synced,
          const ResolvedAudio(input: 'x', engine: AudioEngine.web),
          dir,
        ),
        isNull,
      );
      ready = false;
      expect(await sync.run(_track, _synced, _file, dir), isNull);
      expect(calls, isEmpty);
    },
  );

  test('errors leave the lyrics as they were and can be retried', () async {
    failure = StateError('sin red');
    final sync = create();
    expect(await sync.run(_track, _synced, _file, dir), isNull);
    expect(await service.readAutoOffset(_track, dir), isNull);
    failure = null;
    expect(await sync.run(_track, _synced, _file, dir), -12000);
  });
}
