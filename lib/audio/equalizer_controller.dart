import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio_backend.dart';
import 'eq_model.dart';

/// Estado del ecualizador: bandas, presets propios y persistencia. Es local de
/// cada dispositivo (una Jam nunca lo sincroniza) y solo habla con el motor de
/// audio local.
class EqualizerController extends ChangeNotifier {
  EqualizerController({required this.audio, required this.preferences}) {
    _supported = audio.supportsEqualizer;
    audio.addListener(_audioChanged);
  }
  final AudioBackend audio;
  final SharedPreferences preferences;

  static const enabledKey = 'eqEnabled';
  static const bandsKey = 'eqBands';
  static const autoPreampKey = 'eqAutoPreamp';
  static const presetsKey = 'eqPresets';
  static const maxUserPresets = 30;

  bool enabled = false;
  bool autoPreamp = true;

  /// Comparación A/B: oye el audio sin procesar sin perder el ajuste. No se
  /// guarda; al reiniciar vuelve a procesar.
  bool bypass = false;
  List<EqBand> bands = eqFlatBands();
  List<EqPreset> userPresets = [];
  Timer? _saveTimer;
  bool _disposed = false;
  late bool _supported;

  bool get supported => audio.supportsEqualizer;

  /// El motor está procesando de verdad.
  bool get active => supported && enabled && !bypass;

  List<EqPreset> get presets => [...eqBuiltInPresets, ...userPresets];

  /// Nombre del preset cuyas bandas coinciden exactamente con las actuales.
  String? get presetName {
    for (final preset in presets) {
      if (listEquals(preset.bands, bands)) return preset.name;
    }
    return null;
  }

  void load() {
    enabled = preferences.getBool(enabledKey) ?? false;
    autoPreamp = preferences.getBool(autoPreampKey) ?? true;
    final saved = preferences.getString(bandsKey);
    if (saved != null) {
      try {
        final decoded = jsonDecode(saved);
        if (decoded is List && decoded.isNotEmpty) {
          bands = EqPreset('', [
            for (final b in decoded) EqBand.fromJson(b),
          ]).bands;
        }
      } on FormatException {
        // Ajuste corrupto: se queda plano.
      }
    } else {
      // Versión anterior: solo guardaba ocho ganancias.
      final legacy = preferences.getStringList('eqGains');
      if (legacy != null && legacy.length == eqBandCount) {
        bands = eqBandsWithGains([
          for (final v in legacy) double.tryParse(v) ?? 0,
        ]);
      }
    }
    final rawPresets = preferences.getString(presetsKey);
    if (rawPresets != null) {
      try {
        userPresets = eqPresetsFromJson(rawPresets);
      } on FormatException {
        userPresets = [];
      }
    }
  }

  /// Envía el ajuste actual al motor.
  void apply() => audio.setEqualizer(active, bands, autoPreamp: autoPreamp);

  // Android conoce su soporte tras arrancar: al cambiar, se reenvía el ajuste
  // y la interfaz se actualiza.
  void _audioChanged() {
    if (audio.supportsEqualizer == _supported) return;
    _supported = audio.supportsEqualizer;
    apply();
    notifyListeners();
  }

  void _changed({bool save = true}) {
    apply();
    if (save) _saveSoon();
    notifyListeners();
  }

  void setEnabled(bool value) {
    if (!supported) return;
    enabled = value;
    if (value) bypass = false;
    preferences.setBool(enabledKey, value).ignore();
    _changed(save: false);
  }

  void setBypass(bool value) {
    if (!supported || bypass == value) return;
    bypass = value;
    _changed(save: false);
  }

  void setAutoPreamp(bool value) {
    autoPreamp = value;
    preferences.setBool(autoPreampKey, value).ignore();
    _changed(save: false);
  }

  void setBand(int index, EqBand band) {
    if (index < 0 || index >= bands.length || bands[index] == band) return;
    bands = [...bands]..[index] = band;
    _changed();
  }

  /// Pasos de 0,1 dB.
  void setGain(int index, double gainDb) {
    if (index < 0 || index >= bands.length) return;
    setBand(
      index,
      bands[index].copyWith(gainDb: (gainDb * 10).roundToDouble() / 10),
    );
  }

  /// Doble clic en una banda: devuelve ganancia, frecuencia y Q a su valor
  /// inicial.
  void resetBand(int index) {
    if (index < 0 || index >= bands.length) return;
    setBand(index, EqBand(eqDefaultFrequencies[index]));
  }

  void applyPreset(EqPreset preset) {
    bands = List.of(preset.bands);
    _changed();
  }

  /// Guarda las bandas actuales con [name]; reemplaza un preset propio del
  /// mismo nombre. Devuelve false si el nombre no es válido o choca con uno
  /// de fábrica.
  bool savePreset(String name) {
    final clean = name.trim();
    if (clean.isEmpty || eqBuiltInPresets.any((p) => p.name == clean)) {
      return false;
    }
    final preset = EqPreset(
      clean.length > 40 ? clean.substring(0, 40) : clean,
      bands,
    );
    final next = [
      for (final p in userPresets)
        if (p.name != preset.name) p,
      preset,
    ];
    if (next.length > maxUserPresets) return false;
    userPresets = next;
    _savePresets();
    notifyListeners();
    return true;
  }

  void deletePreset(String name) {
    userPresets = [
      for (final p in userPresets)
        if (p.name != name) p,
    ];
    _savePresets();
    notifyListeners();
  }

  String exportPresets() => eqPresetsToJson(
    userPresets.isEmpty ? [EqPreset('Mi ajuste', bands)] : userPresets,
  );

  /// Añade presets de un JSON exportado. Devuelve cuántos se incorporaron y
  /// lanza FormatException si el texto no sirve.
  int importPresets(String text) {
    final incoming = eqPresetsFromJson(text);
    var added = 0;
    for (final preset in incoming) {
      if (eqBuiltInPresets.any((p) => p.name == preset.name)) continue;
      final others = [
        for (final p in userPresets)
          if (p.name != preset.name) p,
      ];
      if (others.length >= maxUserPresets) break;
      userPresets = [...others, preset];
      added++;
    }
    if (added == 0) {
      throw const FormatException('Los presets ya existen o son de fábrica.');
    }
    _savePresets();
    notifyListeners();
    return added;
  }

  void _savePresets() =>
      preferences.setString(presetsKey, eqPresetsToJson(userPresets)).ignore();

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _saveNow);
  }

  void _saveNow() {
    _saveTimer = null;
    preferences
        .setString(bandsKey, jsonEncode([for (final b in bands) b.toJson()]))
        .ignore();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    audio.removeListener(_audioChanged);
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveNow();
    }
    super.dispose();
  }
}
