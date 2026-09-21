import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/vault_models.dart';
import 'vault_storage_types.dart';

export 'vault_storage_types.dart';

const int defaultMaxVaultFileBytes = 16 * 1024 * 1024;

class VaultRepository {
  VaultRepository({
    Directory? directory,
    Future<Directory> Function()? directoryProvider,
    this.maxFileBytes = defaultMaxVaultFileBytes,
    Future<File> Function(File file, String newPath)? renameFile,
  })  : assert(maxFileBytes > 0),
        _directory = directory,
        _directoryProvider = directoryProvider,
        _renameFile = renameFile;

  final Directory? _directory;
  final Future<Directory> Function()? _directoryProvider;
  final Future<File> Function(File file, String newPath)? _renameFile;
  final int maxFileBytes;

  Future<void> _writeTail = Future<void>.value();
  int _temporaryFileSequence = 0;

  Future<bool> exists() async {
    final result = await inspect();
    return result.state != VaultStorageState.absent;
  }

  /// Loads a validated primary document, or a validated recovery candidate.
  /// Call [inspect] when the caller needs to distinguish safe creation from
  /// corruption, permissions, or recovery-required states.
  Future<EncryptedVaultDocument?> load() async => (await inspect()).document;

  Future<VaultLoadResult> inspect() async {
    final file = await _vaultFile();
    try {
      final primary = await _readCandidate(file, VaultRecoverySource.primary);
      if (primary.permissionDenied) {
        return _permissionDeniedResult(primary.error);
      }
      if (primary.unsupportedVersion) {
        return VaultLoadResult(
          state: VaultStorageState.unsupportedVersion,
          error: primary.error,
        );
      }
      final temporary = await _readTemporaryCandidates(file);
      if (primary.document != null) {
        final newerTemporary = _selectNewestCandidate(
          temporary.where((candidate) => candidate.isNewerRevisionOf(primary)),
        );
        final migrationTemporary =
            _selectLegacyMigrationTemporary(primary, temporary);
        final recovery = newerTemporary ?? migrationTemporary;
        if (recovery != null) {
          return recovery.toLoadResult(VaultStorageState.recoveryAvailable);
        }
        return primary.toLoadResult(VaultStorageState.available);
      }

      final backup = await _readCandidate(
        File('${file.path}.bak'),
        VaultRecoverySource.backup,
      );
      if (backup.permissionDenied) {
        return _permissionDeniedResult(backup.error);
      }
      final recovery = _selectRecoveryCandidate(backup, temporary);
      if (recovery != null) {
        return recovery.toLoadResult(VaultStorageState.recoveryAvailable);
      }

      final allCandidates = <_VaultCandidate>[primary, backup, ...temporary];
      if (allCandidates.every((candidate) => candidate.missing)) {
        return const VaultLoadResult(state: VaultStorageState.absent);
      }
      if (allCandidates.any((candidate) => candidate.permissionDenied)) {
        final denied = allCandidates.firstWhere(
          (candidate) => candidate.permissionDenied,
        );
        return _permissionDeniedResult(denied.error);
      }
      if (allCandidates.any((candidate) => candidate.unsupportedVersion)) {
        final unsupported = allCandidates.firstWhere(
          (candidate) => candidate.unsupportedVersion,
        );
        return VaultLoadResult(
          state: VaultStorageState.unsupportedVersion,
          error: unsupported.error,
        );
      }
      final failed = allCandidates.firstWhere(
        (candidate) => !candidate.missing,
      );
      return VaultLoadResult(
        state: VaultStorageState.corrupt,
        error: failed.error ?? 'Vault candidate could not be validated.',
      );
    } on FileSystemException catch (error) {
      return _permissionDeniedResult(error.message);
    }
  }

  Future<Uint8List?> loadRaw() async => (await inspect()).rawBytes;

  Future<void> recover() async {
    await _serializeWrite(() async {
      final result = await inspect();
      if (!result.canRecover || result.rawBytes == null) {
        throw StateError('No validated recovery candidate is available.');
      }
      final target = await _vaultFile();
      await target.parent.create(recursive: true);
      final tempFile = await _writeTemporaryFile(target, result.rawBytes!);
      File? previousPrimary;
      try {
        if (await target.exists()) {
          previousPrimary = await _rename(
            target,
            '${target.path}.corrupt.${_nextTemporarySuffix()}',
          );
        }
        await _rename(tempFile, target.path);
      } catch (_) {
        if (previousPrimary != null &&
            await previousPrimary.exists() &&
            !await target.exists()) {
          await _rename(previousPrimary, target.path);
        }
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        rethrow;
      }
    });
  }

  Future<void> reset({required String confirmation}) async {
    if (confirmation != 'RESET') {
      throw ArgumentError.value(
        confirmation,
        'confirmation',
        'Reset requires the exact confirmation RESET.',
      );
    }
    await _serializeWrite(() async {
      final file = await _vaultFile();
      final candidates = <File>[
        file,
        File('${file.path}.bak'),
        ...await _temporaryFiles(file),
        ...await _quarantinedFiles(file),
      ];
      for (final candidate in candidates) {
        if (await candidate.exists()) {
          await candidate.delete();
        }
      }
    });
  }

  Future<void> save(EncryptedVaultDocument document) =>
      _saveRaw(document.encode());

  Future<void> importRaw(Uint8List bytes) async {
    _validateRaw(bytes);
    await _saveRaw(bytes);
  }

  Future<void> _saveRaw(Uint8List bytes) async {
    if (bytes.length > maxFileBytes) {
      throw FormatException('Vault file is too large to save.');
    }
    await _serializeWrite(() async {
      final file = await _vaultFile();
      await file.parent.create(recursive: true);
      final tempFile = await _writeTemporaryFile(file, bytes);
      await _replaceWithBackup(file, tempFile);
    });
  }

  Future<void> _serializeWrite(Future<void> Function() action) {
    final operation = _writeTail.then((_) => action());
    _writeTail = operation.catchError((_) {});
    return operation;
  }

  Future<File> _writeTemporaryFile(File target, Uint8List bytes) async {
    final tempFile = File('${target.path}.tmp.${_nextTemporarySuffix()}');
    await tempFile.writeAsBytes(bytes, flush: true);
    return tempFile;
  }

  Future<File> _vaultFile() async {
    final directory = _directory ??
        await (_directoryProvider?.call() ?? getApplicationSupportDirectory());
    return File('${directory.path}${Platform.pathSeparator}vault.pwv');
  }

  Future<File> _rename(File file, String newPath) =>
      _renameFile?.call(file, newPath) ?? file.rename(newPath);

  Future<void> _replaceWithBackup(File target, File tempFile) async {
    final backupFile = File('${target.path}.bak');
    final primary = await _readCandidate(target, VaultRecoverySource.primary);
    if (primary.document != null) {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      await _rename(target, backupFile.path);
      try {
        await _rename(tempFile, target.path);
      } catch (_) {
        if (await backupFile.exists()) {
          await _rename(backupFile, target.path);
        }
        rethrow;
      }
      return;
    }

    if (await target.exists()) {
      await _rename(target, '${target.path}.corrupt.${_nextTemporarySuffix()}');
    }
    try {
      await _rename(tempFile, target.path);
    } catch (_) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  Future<List<_VaultCandidate>> _readTemporaryCandidates(File target) async {
    final files = await _temporaryFiles(target);
    final candidates = <_VaultCandidate>[];
    for (final file in files) {
      candidates.add(await _readCandidate(file, VaultRecoverySource.temporary));
    }
    return candidates;
  }

  _VaultCandidate? _selectRecoveryCandidate(
    _VaultCandidate backup,
    List<_VaultCandidate> temporary,
  ) {
    if (backup.document != null) {
      return _selectNewestCandidate(
            temporary.where((candidate) => candidate.isNewerRevisionOf(backup)),
          ) ??
          _selectLegacyMigrationTemporary(backup, temporary) ??
          backup;
    }

    final validTemporary =
        temporary.where((candidate) => candidate.document != null).toList();
    final vaultIds = validTemporary
        .map((candidate) => candidate.document!.metadata?.vaultId)
        .whereType<String>()
        .toSet();
    if (vaultIds.length > 1 ||
        (vaultIds.isNotEmpty &&
            validTemporary
                .any((candidate) => candidate.document!.metadata == null))) {
      return null;
    }
    return _selectNewestCandidate(validTemporary);
  }

  _VaultCandidate? _selectLegacyMigrationTemporary(
    _VaultCandidate legacyCandidate,
    List<_VaultCandidate> temporary,
  ) {
    if (legacyCandidate.document?.metadata != null) {
      return null;
    }
    final legacyModifiedAt = legacyCandidate.modifiedAt;
    if (legacyModifiedAt == null) {
      return null;
    }
    final plausibleCandidates = temporary.where((candidate) {
      final metadata = candidate.document?.metadata;
      return metadata != null &&
          metadata.keyGeneration == 1 &&
          metadata.revision == 0 &&
          candidate.modifiedAt != null &&
          candidate.modifiedAt!.isAfter(legacyModifiedAt);
    }).toList();
    return plausibleCandidates.length == 1 ? plausibleCandidates.single : null;
  }

  _VaultCandidate? _selectNewestCandidate(
    Iterable<_VaultCandidate> candidates,
  ) {
    final validCandidates =
        candidates.where((candidate) => candidate.document != null).toList()
          ..sort((first, second) {
            final firstMetadata = first.document!.metadata;
            final secondMetadata = second.document!.metadata;
            if (firstMetadata != null && secondMetadata != null) {
              final revisionOrder =
                  secondMetadata.revision.compareTo(firstMetadata.revision);
              if (revisionOrder != 0) {
                return revisionOrder;
              }
            }
            return second.modifiedAt!.compareTo(first.modifiedAt!);
          });
    return validCandidates.firstOrNull;
  }

  Future<List<File>> _temporaryFiles(File target) =>
      _filesWithPrefix(target, '${target.uri.pathSegments.last}.tmp');

  Future<List<File>> _quarantinedFiles(File target) =>
      _filesWithPrefix(target, '${target.uri.pathSegments.last}.corrupt.');

  Future<List<File>> _filesWithPrefix(File target, String prefix) async {
    if (!await target.parent.exists()) {
      return const [];
    }
    final entities = await target.parent.list().toList();
    final files = entities
        .whereType<File>()
        .where((file) => file.uri.pathSegments.last.startsWith(prefix))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<_VaultCandidate> _readCandidate(
    File file,
    VaultRecoverySource source,
  ) async {
    try {
      if (!await file.exists()) {
        return _VaultCandidate.missing(source);
      }
      final length = await file.length();
      if (length <= 0) {
        return _VaultCandidate.invalid(source, 'Vault file is empty.');
      }
      if (length > maxFileBytes) {
        return _VaultCandidate.invalid(source, 'Vault file is too large.');
      }
      final bytes = Uint8List.fromList(await file.readAsBytes());
      final document = _validateRaw(bytes);
      return _VaultCandidate.valid(
        source,
        document,
        bytes,
        await file.lastModified(),
      );
    } on FileSystemException catch (error) {
      return _VaultCandidate.permissionDenied(source, error.message);
    } on FormatException catch (error) {
      final message = error.message.toString();
      if (message.startsWith('Unsupported vault document version:')) {
        return _VaultCandidate.unsupportedVersion(source, message);
      }
      return _VaultCandidate.invalid(source, message);
    } on Object catch (error) {
      return _VaultCandidate.invalid(source, 'Invalid vault file: $error');
    }
  }

  EncryptedVaultDocument _validateRaw(Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw FormatException('Vault file is too large.');
    }
    return EncryptedVaultDocument.decode(bytes);
  }

  String _nextTemporarySuffix() =>
      '${DateTime.now().microsecondsSinceEpoch}.${_temporaryFileSequence++}';

  VaultLoadResult _permissionDeniedResult(String? error) => VaultLoadResult(
        state: VaultStorageState.permissionDenied,
        error: error ?? 'Vault storage permission was denied.',
      );
}

class _VaultCandidate {
  const _VaultCandidate._({
    required this.source,
    this.document,
    this.rawBytes,
    this.modifiedAt,
    this.error,
    this.missing = false,
    this.permissionDenied = false,
    this.unsupportedVersion = false,
  });

  factory _VaultCandidate.missing(VaultRecoverySource source) =>
      _VaultCandidate._(source: source, missing: true);

  factory _VaultCandidate.valid(
    VaultRecoverySource source,
    EncryptedVaultDocument document,
    Uint8List rawBytes,
    DateTime modifiedAt,
  ) =>
      _VaultCandidate._(
        source: source,
        document: document,
        rawBytes: rawBytes,
        modifiedAt: modifiedAt,
      );

  factory _VaultCandidate.invalid(VaultRecoverySource source, String error) =>
      _VaultCandidate._(source: source, error: error);

  factory _VaultCandidate.permissionDenied(
    VaultRecoverySource source,
    String error,
  ) =>
      _VaultCandidate._(source: source, error: error, permissionDenied: true);

  factory _VaultCandidate.unsupportedVersion(
    VaultRecoverySource source,
    String error,
  ) =>
      _VaultCandidate._(source: source, error: error, unsupportedVersion: true);

  final VaultRecoverySource source;
  final EncryptedVaultDocument? document;
  final Uint8List? rawBytes;
  final DateTime? modifiedAt;
  final String? error;
  final bool missing;
  final bool permissionDenied;
  final bool unsupportedVersion;

  bool isNewerRevisionOf(_VaultCandidate primary) {
    final candidateMetadata = document?.metadata;
    final primaryMetadata = primary.document?.metadata;
    if (candidateMetadata != null && primaryMetadata != null) {
      return candidateMetadata.vaultId == primaryMetadata.vaultId &&
          candidateMetadata.revision > primaryMetadata.revision;
    }
    final candidateModifiedAt = modifiedAt;
    final primaryModifiedAt = primary.modifiedAt;
    return candidateMetadata == null &&
        primaryMetadata == null &&
        candidateModifiedAt != null &&
        primaryModifiedAt != null &&
        candidateModifiedAt.isAfter(primaryModifiedAt);
  }

  VaultLoadResult toLoadResult(VaultStorageState state) => VaultLoadResult(
        state: state,
        document: document,
        rawBytes: rawBytes,
        recoverySource: source,
        error: error,
      );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
