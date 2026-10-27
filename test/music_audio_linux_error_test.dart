import 'package:aurora_music/audio/music_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missingSharedLibrary extrae la biblioteca que falta', () {
    expect(
      missingSharedLibrary(
        "Failed to load dynamic library 'libflutter_soloud_plugin.so': "
        'libFLAC.so.14: cannot open shared object file: '
        'No such file or directory',
      ),
      'libFLAC.so.14',
    );
    expect(
      missingSharedLibrary(
        'libvorbis.so.0.4.9: cannot open shared object file',
      ),
      'libvorbis.so.0.4.9',
    );
    expect(missingSharedLibrary('SoLoud init failed'), isNull);
  });
}
