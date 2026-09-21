# Cipherbook Architecture

## Runtime flow

`main.dart` creates `CipherbookApp`. The app wires concrete services into one
`VaultController`, and `HomePage` observes that controller through
`ChangeNotifier`.

The controller owns the in-memory session only: decrypted vault data, the DEK,
the current KEK, auto-lock state, and the session generation used to reject
late async results after locking.

After a successful unlock, the controller may start low-frequency LAN discovery
and synchronization while the app is in the foreground. LAN transport exchanges
encrypted vault documents; it never exposes plaintext passwords or the master
password to the network.

## Boundaries

- `lib/models/`: validated wire and domain models. These files must not depend
  on Flutter widgets or platform APIs.
- `lib/services/`: crypto, file storage, import/export, clipboard, TOTP,
  password generation, device-key adapters, and LAN pairing/sync.
- `lib/state/`: orchestration and session state. UI calls this layer instead of
  writing files or invoking crypto directly.
- `lib/ui/`: screens and widgets. UI owns controllers/focus/navigation, while
  the controller owns vault mutations and security decisions.
- `android/` and `windows/`: platform bridges only. Android uses the Keystore
  and biometric prompt; Windows uses Windows Hello verification plus DPAPI for
  the local wrapped-key cache. The Dart layer never receives a plaintext
  password from either platform bridge.

The current mobile UI has an Android-specific shell and a shared responsive
content layer. iOS is not yet an available target: it needs an iOS host project,
Keychain/LocalAuthentication bridge, local-network entitlements, and Apple
signing configuration before it can be built or distributed.

## Persistence flow

Writes are serialized by `VaultRepository`. A new document is written to a
temporary file, the previous valid primary is retained as `.bak`, and failed
or ambiguous candidates are surfaced for recovery instead of being silently
overwritten.

## Change rules

1. Add domain behavior to a service or controller, not to a widget.
2. Keep sensitive values out of logs, error messages, and test output.
3. Add a focused test for every storage, crypto, or session-state change.
4. Keep public types in their own files once they are shared across layers.
5. Keep generated build output and local installers out of source changes unless
   a release artifact is explicitly being published.
