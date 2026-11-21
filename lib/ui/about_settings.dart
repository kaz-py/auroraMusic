import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Contenido de «Acerca de»: nombre, versión instalada y nota de uso.
class AboutSettings extends StatefulWidget {
  const AboutSettings({super.key});

  @override
  State<AboutSettings> createState() => _AboutSettingsState();
}

class _AboutSettingsState extends State<AboutSettings> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? text;
    try {
      final p = await PackageInfo.fromPlatform();
      text = p.buildNumber.isEmpty
          ? p.version
          : '${p.version} (${p.buildNumber})';
    } catch (_) {
      // Sin plugin (pruebas o plataforma sin soporte): solo se omite la versión.
    }
    if (mounted) setState(() => _version = text);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Aurora', style: Theme.of(context).textTheme.titleMedium),
      if (_version != null)
        Text('Versión $_version', key: const ValueKey('about-version')),
      const SizedBox(height: 12),
      const Text(
        'Tu biblioteca permanece en este dispositivo. Utiliza enlaces y '
        'contenido que tengas permiso para reproducir y guardar.',
        style: TextStyle(fontSize: 13, height: 1.6),
      ),
    ],
  );
}
