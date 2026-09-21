import 'dart:typed_data';

import '../models/vault_models.dart';
import '../services/crypto_service.dart';

class ImportPlan {
  const ImportPlan({
    required this.sessionGeneration,
    required this.hadVaultAtPreview,
    required this.rawBytes,
    required this.importedDocument,
    required this.importedSession,
    required this.summary,
  });

  final int sessionGeneration;
  final bool hadVaultAtPreview;
  final Uint8List rawBytes;
  final EncryptedVaultDocument importedDocument;
  final VaultSession importedSession;
  final ImportMergeSummary summary;
}
