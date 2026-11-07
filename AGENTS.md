# Repository Guidelines

## Project Structure & Module Organization
This is a Flutter app (`cipherbook`) targeting Android and Windows. It stores sensitive vault data locally and supports encrypted LAN synchronization.
- `lib/`: application code
- `lib/models/`: data models
- `lib/services/`: crypto, storage, Bitwarden interchange, quick unlock, LAN sync, and utility services
- `lib/state/`: session/controller logic and import plans
- `lib/ui/`: screens and UI widgets
- `test/`: unit and flow tests (`*_test.dart`)
- `android/`, `windows/`: platform host code
- `docs/`: architecture, development, security, and release documentation
- `tools/`: helper scripts (for example Android license setup)

Keep business logic in `lib/services/` and UI code in `lib/ui/` to avoid cross-layer coupling.

## Build, Test, and Development Commands
Run from repository root:
- `flutter pub get`: install dependencies
- `flutter analyze --no-pub lib test`: static analysis with `flutter_lints`
- `flutter test --no-pub`: run all tests
- `flutter test --no-pub test/<name>_test.dart`: run a focused test
- `flutter run -d windows` or `flutter run -d android`: local development run
- `flutter build apk --release`: build Android release APK
- `flutter build windows --release`: build Windows release binary

Windows builds require the Visual Studio C++ Build Tools environment. If your machine has path/encoding issues, prefer ASCII-only build paths for release builds. Exact commands are documented in `docs/development.md`.

## Coding Style & Naming Conventions
- Follow `analysis_options.yaml` (`package:flutter_lints/flutter.yaml`).
- Use 2-space indentation and Dart formatter defaults.
- File names: `snake_case.dart`.
- Classes/enums: `PascalCase`.
- Methods/variables/parameters: `lowerCamelCase`.
- Keep widgets small and composable; move non-UI logic to services/controllers.

## Testing Guidelines
- Framework: `flutter_test`.
- Test files must end with `*_test.dart` under `test/`.
- Add or update tests for every behavior change in services/state layers, especially crypto, storage recovery, session locking, LAN sync, and Bitwarden import matching.
- Before opening a PR, run:
  - `dart format lib test`
  - `flutter analyze --no-pub lib test`
  - `flutter test --no-pub`

No explicit coverage gate is configured; treat meaningful regression coverage as required.

## Documentation Guidelines

- Keep `README.md`, `CHANGELOG.md`, `docs/architecture.md`, `docs/security.md`, and `docs/release.md` aligned with actual behavior.
- `pubspec.yaml` is the only source of the application version and build number.
- Document unsupported boundaries explicitly; do not claim Bitwarden parity, independent security audit, production signing, or iOS support.
- Keep platform-specific build and ADB commands in `docs/development.md` rather than duplicating them across many files.

## Commit & Pull Request Guidelines
Recent history shows short, action-focused commit subjects (Chinese and English are both used). Follow this style:
- Subject line: concise, imperative, and scoped (for example, `Add Windows device key store plugin`).
- One logical change per commit.

PRs should include:
- What changed and why
- Risk/impact summary (crypto, storage, import/export, platform code)
- Linked issue (if available)
- Screenshots or short recordings for UI changes
- Verification notes with exact commands run

## Security & Configuration Tips
This project handles sensitive vault data. Do not log secrets, keys, plaintext passwords, TOTP seeds, Bitwarden plaintext exports, or LAN device tokens. Do not commit `build/`, `dist/`, signing keys, real vaults, or plaintext exchange files. Validate crypto/storage changes with focused tests before merging.

See `docs/security.md` for the threat model and `SECURITY.md` for private vulnerability reporting.
