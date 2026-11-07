# Repository Guidelines

## Project Structure & Module Organization

Aurora is a Flutter/Dart music player for Windows and Android. Shared models and platform contracts live in `lib/core/`; playback is in `lib/audio/`, extraction in `lib/sources/`, and screens in `lib/ui/`. The application controller coordinates these modules, while the local database stores the library. Android platform integration lives under `android/app/src/main/kotlin/`. Windows runners live in `windows/`. Tests belong in `test/`; setup utilities belong in `scripts/`.

## Build, Test, and Development Commands

- `flutter pub get`: install dependencies using the committed lockfile.
- `flutter run -d windows`: start the desktop application.
- `flutter run -d <device-id>`: start on an Android device listed by `flutter devices`.
- `flutter analyze`: check Dart types and configured Flutter lints.
- `flutter test`: run unit and widget tests.
- `dart format lib test`: format Dart sources with the Flutter SDK's Dart executable.
- `flutter build windows --release`: build the Windows distribution.
- `flutter build apk --debug`: build an Android development APK. Configure release signing before distributing release builds.

## Coding Style & Naming Conventions

Use standard Dart formatting with two-space indentation. Name files `snake_case.dart`, classes `PascalCase`, and members `lowerCamelCase`. Keep platform operations outside widgets and represent asynchronous loading, failure, and cancellation explicitly. Follow `analysis_options.yaml`; avoid speculative abstractions and new packages when existing tools cover the requirement.

## Testing Guidelines

Use `flutter_test`; name files `*_test.dart`. Test queue transitions, persistence, extraction validation, cancellation, and recovery from failures. Widget tests should cover narrow layouts and enlarged text. Hardware playback, Bluetooth controls, background audio, and native packaging require device checks in addition to automated tests. Document untested hardware rather than claiming universal compatibility.

UI changes (`lib/ui/`, `lib/theme/`, `lib/main.dart`) are covered by the UI guard in `test/ui_guard/`: a theme × mode × width × text-scale × screen matrix that fails on overflow, contrast below 3:1, touch targets under 40x40 on phones, and content cut by the screen edge. `flutter test` runs the `quick` tier; run the full matrix with `flutter test test/ui_guard --dart-define=UI_GUARD=full`. Accepted failures live in `test/ui_guard/known_issues.dart` and may only shrink. Optional pre-commit hook: `scripts/install_hooks.ps1` / `scripts/install_hooks.sh`. See `docs/ui_guard.md`.

## Commit & Pull Request Guidelines

Git history began with `Initial commit`; no established message convention exists. Use short, imperative subjects describing the change. Pull requests should explain behavior, include validation commands and results, link relevant issues, and attach screenshots for interface changes.

## Security & Configuration

Never commit signing keys, cookies, executable downloads, or personal library files. Validate external inputs, keep TLS verification enabled, and execute tools with argument lists rather than shell interpolation. Pin packaged dependencies and preserve their license notices.
