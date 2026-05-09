# Repository Guidelines

## Project Structure & Module Organization
This is a Flutter app (`cipherbook`) targeting Android and Windows.
- `lib/`: application code
- `lib/models/`: data models
- `lib/services/`: crypto, storage, import/export, and utility services
- `lib/state/`: state/controller logic
- `lib/ui/`: screens and UI widgets
- `test/`: unit and flow tests (`*_test.dart`)
- `android/`, `windows/`: platform host code
- `tools/`: helper scripts (for example Android license setup)

Keep business logic in `lib/services/` and UI code in `lib/ui/` to avoid cross-layer coupling.

## Build, Test, and Development Commands
Run from repository root:
- `flutter pub get`: install dependencies
- `flutter analyze lib test`: static analysis with `flutter_lints`
- `flutter test`: run all tests
- `flutter run -d windows` or `flutter run -d android`: local development run
- `flutter build apk --release`: build Android release APK
- `flutter build windows --release`: build Windows release binary

If your machine has path/encoding issues, prefer ASCII-only build paths for release builds.

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
- Add or update tests for every behavior change in services/state layers.
- Before opening a PR, run:
  - `flutter analyze lib test`
  - `flutter test`

No explicit coverage gate is configured; treat meaningful regression coverage as required.

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
This project handles sensitive vault data. Do not log secrets, keys, plaintext passwords, or TOTP seeds. Validate crypto/storage changes with focused tests before merging.
