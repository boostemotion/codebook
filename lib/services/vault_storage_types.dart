import 'dart:typed_data';

import '../models/vault_models.dart';

enum VaultStorageState {
  loading,
  absent,
  available,
  corrupt,
  unsupportedVersion,
  permissionDenied,
  recoveryAvailable,
}

enum VaultRecoverySource { primary, backup, temporary }

class VaultLoadResult {
  const VaultLoadResult({
    required this.state,
    this.document,
    this.rawBytes,
    this.recoverySource,
    this.error,
  });

  final VaultStorageState state;
  final EncryptedVaultDocument? document;
  final Uint8List? rawBytes;
  final VaultRecoverySource? recoverySource;
  final String? error;

  bool get canCreate => state == VaultStorageState.absent;
  bool get canRecover => state == VaultStorageState.recoveryAvailable;
}
