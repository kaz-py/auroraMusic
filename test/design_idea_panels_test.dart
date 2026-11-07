import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/library/local_file_metadata.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/studio/downloads_studio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const track = Track(
  id: 'studio-fixture',
  title: 'Puentes',
  artist: 'Aurora Test',
  album: 'Archivo',
  duration: Duration(minutes: 3),
  pageUrl: 'https://example.test/track',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'Newsreader': 'assets/fonts/newsreader/Newsreader-Variable.ttf',
      'Plus Jakarta Sans':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  test('file sizes excludes missing paths and directories', () async {
    final dir = await Directory.systemTemp.createTemp('aurora_sizes_');
    try {
      final file = await File(
        '${dir.path}/fixture.bin',
      ).writeAsBytes([1, 2, 3]);
      expect(
        await localFileSizes([
          '',
          file.path,
          file.path,
          dir.path,
          '${dir.path}/missing',
        ]),
        {file.path: 3},
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  testWidgets('downloads uses real statuses and fits narrow enlarged text', (
    tester,
  ) async {
    final c = (await tester.runAsync(
      () => createTestController(tracks: [track]),
    ))!;
    addTearDown(() => closeTestController(c));
    c.downloads.add(
      DownloadJob(
        id: 'fixture-download',
        track: track,
        status: DownloadStatus.downloading,
        progress: .25,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: DownloadsStudioPage(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 en progreso'), findsOneWidget);
    final usb = find.text('Exportar a USB · pendiente');
    await tester.scrollUntilVisible(
      usb,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(usb);
    await tester.pumpAndSettle();
    await tester.tap(usb);
    await tester.pumpAndSettle();
    expect(
      find.text('Exportar a USB: no implementado todavía.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'studio panels review captures use native fonts and offline fixtures',
    (tester) async {
      final c = (await tester.runAsync(
        () => createTestController(tracks: [track]),
      ))!;
      addTearDown(() => closeTestController(c));
      final illustrated = track.copyWith(
        artworkUrl: 'asset:assets/design_idea/letras_din_micas_aurora_01.png',
      );
      c.queue = [illustrated];
      c.queueIndex = 0;
      await tester.runAsync(() => c.playQueueAt(0));
      await c.audio.seek(const Duration(seconds: 8));
      c.downloads.add(
        DownloadJob(
          id: 'capture-active',
          track: illustrated,
          status: DownloadStatus.downloading,
          progress: .68,
        ),
      );
      c.downloads.add(
        DownloadJob(
          id: 'capture-completed',
          track: illustrated,
          status: DownloadStatus.completed,
          localPath: '${c.supportDirectory.path}/fixture.mp3',
          progress: 1,
        ),
      );
      await tester.runAsync(
        () => File(
          c.downloads.last.localPath!,
        ).writeAsBytes(List.filled(8192, 0)),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final page in ['downloads']) {
        for (final size in [const Size(1286, 1913), const Size(320, 800)]) {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(
            MaterialApp(
              theme: auroraTheme(Brightness.dark, const Color(0xffe86927)),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(size.width == 320 ? 2 : 1),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: RepaintBoundary(
                  key: const ValueKey('studio-review'),
                  child: ColoredBox(
                    color: const Color(0xff151312),
                    child: DownloadsStudioPage(controller: c),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            for (final widget in tester.widgetList<Image>(find.byType(Image))) {
              await precacheImage(
                widget.image,
                tester.element(find.byKey(const ValueKey('studio-review'))),
              );
            }
          });
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 200));
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('studio-review')),
            );
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('build/ui-review').create(recursive: true);
            await File(
              'build/ui-review/studio-$page-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
}
