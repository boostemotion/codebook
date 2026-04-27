# Cipherbook

Local-first encrypted password vault for Android and Windows.

## Implemented

- Encrypted local vault file
- Password-based unlock with Argon2id-derived key encryption key
- Random per-vault data encryption key wrapping
- Import / export of encrypted vault snapshots
- Import preview with merge summary before applying changes
- Optional dedicated export password for re-encrypted snapshots
- Merge on import using `itemId`, `updatedAt`, and tombstones
- Change master password without re-encrypting vault contents
- Search, password generation, and clipboard auto-clear
- Auto-lock on inactivity and app backgrounding
- Live TOTP codes from Base32 secrets or otpauth URIs
- Device-bound quick unlock flow on the Dart side, pending native bridge wiring

## Bootstrap

The current workspace did not have Flutter installed, so the app code and tests were added manually.

To generate the Android and Windows host projects after installing Flutter:

```powershell
flutter create . --platforms=android,windows
flutter pub get
flutter test
flutter run -d windows
```

If `flutter create .` reports conflicts, keep the existing `lib/`, `test/`, `pubspec.yaml`, and overwrite the generated host runner files.

## Platform bridge

The Dart side already defines the `dev.codex.cipherbook/device_key_store` method channel.

Expected native methods:

- `isSupported() -> bool`
- `storeWrappedDek(Uint8List bytes) -> void`
- `readWrappedDek() -> Uint8List?`
- `clear() -> void`

Recommended implementation:

- Android: Keystore-generated non-exportable key protects the cached KEK material.
- Windows: DPAPI-protected bytes bind the cached KEK to the local user profile.

## Current gaps

- Android and Windows host runner projects still need to be generated locally with Flutter.
- Quick unlock is only defined as a Dart-side bridge; native Keystore and DPAPI handlers are not wired yet.
- Export path selection uses a save dialog on desktop and a directory picker on Android.
