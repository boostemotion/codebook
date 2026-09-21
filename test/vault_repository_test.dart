import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/services/vault_repository.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cipherbook-repository-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('reports an absent vault only when no vault candidates exist', () async {
    final repository = VaultRepository(directory: directory);

    final result = await repository.inspect();

    expect(result.state, VaultStorageState.absent);
    expect(result.document, isNull);
  });

  test('offers a validated backup for recovery when primary is corrupt',
      () async {
    final repository = VaultRepository(directory: directory);
    final backup =
        File('${directory.path}${Platform.pathSeparator}vault.pwv.bak');
    await backup.writeAsBytes(_document().encode());
    await File('${directory.path}${Platform.pathSeparator}vault.pwv')
        .writeAsString('not a vault');

    final result = await repository.inspect();

    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.document, isNotNull);
    expect(result.recoverySource, VaultRecoverySource.backup);
  });

  test('does not treat a corrupt primary as an absent vault', () async {
    final repository = VaultRepository(directory: directory);
    await File('${directory.path}${Platform.pathSeparator}vault.pwv')
        .writeAsString('not a vault');

    final result = await repository.inspect();

    expect(result.state, VaultStorageState.corrupt);
    expect(result.document, isNull);
  });

  test('rejects oversized candidates before decoding them', () async {
    final repository = VaultRepository(
      directory: directory,
      maxFileBytes: 16,
    );
    await File('${directory.path}${Platform.pathSeparator}vault.pwv')
        .writeAsBytes(Uint8List(17));

    final result = await repository.inspect();

    expect(result.state, VaultStorageState.corrupt);
    expect(result.error, contains('too large'));
  });

  test('serializes concurrent saves and leaves a validated backup', () async {
    final repository = VaultRepository(directory: directory);
    final first = _document(cipherText: Uint8List.fromList([1]));
    final second = _document(cipherText: Uint8List.fromList([2]));

    await Future.wait([repository.save(first), repository.save(second)]);
    final result = await repository.inspect();
    final backup =
        File('${directory.path}${Platform.pathSeparator}vault.pwv.bak');

    expect(result.state, VaultStorageState.available);
    expect(result.document, isNotNull);
    expect(await backup.exists(), isTrue);
    expect(
      EncryptedVaultDocument.decode(
        Uint8List.fromList(await backup.readAsBytes()),
      ),
      isA<EncryptedVaultDocument>(),
    );
  });

  test('keeps a valid primary over a temporary document from another vault',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    await primary.writeAsBytes(_document(revision: 3).encode());
    await File('${primary.path}.tmp.other-vault').writeAsBytes(
      _document(vaultId: 'unrelated-vault', revision: 99).encode(),
    );

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.available);
    expect(result.recoverySource, VaultRecoverySource.primary);
    expect(result.document!.metadata!.vaultId, 'repository-test');
    expect(result.document!.metadata!.revision, 3);
  });

  test(
      'offers the newest matching temporary revision without replacing primary',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final olderTemporary = File('${primary.path}.tmp.01-older');
    final newerTemporary = File('${primary.path}.tmp.02-newer');
    await primary.writeAsBytes(_document(revision: 3).encode());
    await olderTemporary.writeAsBytes(_document(revision: 4).encode());
    await newerTemporary.writeAsBytes(_document(revision: 5).encode());
    final primaryModifiedAt = await primary.lastModified();
    await olderTemporary.setLastModified(
      primaryModifiedAt.add(const Duration(seconds: 1)),
    );
    await newerTemporary.setLastModified(
      primaryModifiedAt.add(const Duration(seconds: 2)),
    );

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.recoverySource, VaultRecoverySource.temporary);
    expect(result.document!.metadata!.revision, 5);
    expect(
      EncryptedVaultDocument.decode(
        Uint8List.fromList(await primary.readAsBytes()),
      ).metadata!.revision,
      3,
    );
  });

  test('offers the newest temporary file when primary and backup are corrupt',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final olderTemporary = File('${primary.path}.tmp.01-older');
    final newerTemporary = File('${primary.path}.tmp.02-newer');
    await primary.writeAsString('corrupt primary');
    await File('${primary.path}.bak').writeAsString('corrupt backup');
    await olderTemporary.writeAsBytes(_document(revision: 2).encode());
    await newerTemporary.writeAsBytes(_document(revision: 3).encode());
    final primaryModifiedAt = await primary.lastModified();
    await olderTemporary.setLastModified(
      primaryModifiedAt.add(const Duration(seconds: 1)),
    );
    await newerTemporary.setLastModified(
      primaryModifiedAt.add(const Duration(seconds: 2)),
    );

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.recoverySource, VaultRecoverySource.temporary);
    expect(result.document!.metadata!.revision, 3);
  });

  test('uses the newest legacy temporary file when metadata is unavailable',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final olderTemporary = File('${primary.path}.tmp.01-older');
    final newerTemporary = File('${primary.path}.tmp.02-newer');
    await primary.writeAsString('corrupt primary');
    await File('${primary.path}.bak').writeAsString('corrupt backup');
    await olderTemporary.writeAsBytes(
      _document(legacy: true, cipherText: Uint8List.fromList([1])).encode(),
    );
    await newerTemporary.writeAsBytes(
      _document(legacy: true, cipherText: Uint8List.fromList([2])).encode(),
    );
    final modifiedAt = DateTime.now();
    await olderTemporary.setLastModified(modifiedAt);
    await newerTemporary.setLastModified(
      modifiedAt.add(const Duration(seconds: 1)),
    );

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.recoverySource, VaultRecoverySource.temporary);
    expect(result.document!.version, legacyVaultDocumentVersion);
    expect(result.document!.payload.cipherText, Uint8List.fromList([2]));
  });

  test('surfaces a first v2 migration temporary over a valid legacy primary',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final temporary = File('${primary.path}.tmp.migration');
    await primary.writeAsBytes(
      _document(legacy: true, cipherText: Uint8List.fromList([1])).encode(),
    );
    await temporary.writeAsBytes(
      _document(revision: 0, cipherText: Uint8List.fromList([2])).encode(),
    );
    final primaryModifiedAt = await primary.lastModified();
    await temporary.setLastModified(
      primaryModifiedAt.add(const Duration(seconds: 1)),
    );

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.recoverySource, VaultRecoverySource.temporary);
    expect(result.document!.version, vaultDocumentVersion);
    expect(result.document!.metadata!.revision, 0);
    expect(
      EncryptedVaultDocument.decode(
        Uint8List.fromList(await primary.readAsBytes()),
      ).version,
      legacyVaultDocumentVersion,
    );
  });

  test('keeps a legacy primary over a non-migration v2 temporary candidate',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final temporary = File('${primary.path}.tmp.unrelated');
    await primary.writeAsBytes(
      _document(legacy: true, cipherText: Uint8List.fromList([1])).encode(),
    );
    await temporary.writeAsBytes(
      _document(
        vaultId: 'unrelated-vault',
        revision: 99,
        cipherText: Uint8List.fromList([2]),
      ).encode(),
    );
    final primaryModifiedAt = await primary.lastModified();
    await temporary.setLastModified(
      primaryModifiedAt.add(const Duration(seconds: 1)),
    );

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.available);
    expect(result.recoverySource, VaultRecoverySource.primary);
    expect(
      EncryptedVaultDocument.decode(
        Uint8List.fromList(await primary.readAsBytes()),
      ).version,
      legacyVaultDocumentVersion,
    );
  });

  test('surfaces a newer legacy temporary over a valid primary', () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final temporary = File('${primary.path}.tmp.02-newer');
    await primary.writeAsBytes(
      _document(legacy: true, cipherText: Uint8List.fromList([1])).encode(),
    );
    await temporary.writeAsBytes(
      _document(legacy: true, cipherText: Uint8List.fromList([2])).encode(),
    );
    final modifiedAt = DateTime.now();
    await primary.setLastModified(modifiedAt);
    await temporary.setLastModified(
      modifiedAt.add(const Duration(seconds: 1)),
    );

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.recoverySource, VaultRecoverySource.temporary);
    expect(result.document!.payload.cipherText, Uint8List.fromList([2]));
  });

  test('surfaces a newer legacy temporary over a valid backup', () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final backup = File('${primary.path}.bak');
    final temporary = File('${primary.path}.tmp.02-newer');
    await primary.writeAsString('corrupt primary');
    await backup.writeAsBytes(
      _document(legacy: true, cipherText: Uint8List.fromList([1])).encode(),
    );
    await temporary.writeAsBytes(
      _document(legacy: true, cipherText: Uint8List.fromList([2])).encode(),
    );
    final modifiedAt = DateTime.now();
    await backup.setLastModified(modifiedAt);
    await temporary.setLastModified(
      modifiedAt.add(const Duration(seconds: 1)),
    );

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.recoverySource, VaultRecoverySource.temporary);
    expect(result.document!.payload.cipherText, Uint8List.fromList([2]));
  });

  test(
      'surfaces a first v2 migration temporary over corrupt primary and legacy backup',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final backup = File('${primary.path}.bak');
    final temporary = File('${primary.path}.tmp.migration');
    await primary.writeAsString('corrupt primary');
    await backup.writeAsBytes(
      _document(legacy: true, cipherText: Uint8List.fromList([1])).encode(),
    );
    await temporary.writeAsBytes(
      _document(revision: 0, cipherText: Uint8List.fromList([2])).encode(),
    );
    final backupModifiedAt = await backup.lastModified();
    await temporary.setLastModified(
      backupModifiedAt.add(const Duration(seconds: 1)),
    );

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.recoverySource, VaultRecoverySource.temporary);
    expect(result.document!.version, vaultDocumentVersion);
    expect(result.document!.metadata!.revision, 0);
    expect(
      EncryptedVaultDocument.decode(
        Uint8List.fromList(await backup.readAsBytes()),
      ).version,
      legacyVaultDocumentVersion,
    );
  });

  test('offers a higher revision even when timestamps are equal', () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final temporary = File('${primary.path}.tmp.02-newer');
    await primary.writeAsBytes(_document(revision: 3).encode());
    await temporary.writeAsBytes(_document(revision: 5).encode());
    final modifiedAt = DateTime.now();
    await primary.setLastModified(modifiedAt);
    await temporary.setLastModified(modifiedAt);

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.recoverySource, VaultRecoverySource.temporary);
    expect(result.document!.metadata!.revision, 5);
  });

  test('prefers a newer matching temporary document when primary is corrupt',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final backup = File('${primary.path}.bak');
    final temporary = File('${primary.path}.tmp.02-newer');
    await primary.writeAsString('corrupt primary');
    await backup.writeAsBytes(_document(revision: 4).encode());
    await temporary.writeAsBytes(_document(revision: 5).encode());
    await temporary.setLastModified(
      (await backup.lastModified()).add(const Duration(seconds: 1)),
    );

    final repository = VaultRepository(directory: directory);
    final result = await repository.inspect();

    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.recoverySource, VaultRecoverySource.temporary);
    expect(result.document!.metadata!.revision, 5);

    await repository.recover();
    final recovered = await repository.inspect();
    expect(recovered.state, VaultStorageState.available);
    expect(recovered.document!.metadata!.revision, 5);
    expect(
      (await directory.list().toList()).whereType<File>().any(
            (file) =>
                file.uri.pathSegments.last.startsWith('vault.pwv.corrupt.'),
          ),
      isTrue,
    );
  });

  test('failed recovery restores a valid primary and retains the candidate',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final temporary = File('${primary.path}.tmp.02-newer');
    await primary.writeAsBytes(_document(revision: 4).encode());
    await temporary.writeAsBytes(_document(revision: 5).encode());
    await temporary.setLastModified(
      (await primary.lastModified()).add(const Duration(seconds: 1)),
    );
    final repository = VaultRepository(
      directory: directory,
      renameFile: (file, path) {
        if (file.path.contains('.tmp.') && path == primary.path) {
          throw FileSystemException('Synthetic recovery replacement failure');
        }
        return file.rename(path);
      },
    );

    await expectLater(
        repository.recover(), throwsA(isA<FileSystemException>()));

    expect(
      EncryptedVaultDocument.decode(
        Uint8List.fromList(await primary.readAsBytes()),
      ).metadata!.revision,
      4,
    );
    expect(await temporary.exists(), isTrue);
    final result = await repository.inspect();
    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.document!.metadata!.revision, 5);
  });

  test('future-version primary takes precedence over supported candidates',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final supportedBackup = File('${primary.path}.bak');
    final supportedTemporary = File('${primary.path}.tmp.supported');
    await primary.writeAsBytes(_unsupportedDocumentBytes());
    await supportedBackup.writeAsBytes(_document(revision: 2).encode());
    await supportedTemporary.writeAsBytes(_document(revision: 3).encode());

    final repository = VaultRepository(directory: directory);
    final result = await repository.inspect();

    expect(result.state, VaultStorageState.unsupportedVersion);
    expect(result.document, isNull);
    expect(result.recoverySource, isNull);
    expect(result.error, contains('Unsupported vault document version'));
    expect(await primary.exists(), isTrue);
    expect(await supportedBackup.exists(), isTrue);
    expect(await supportedTemporary.exists(), isTrue);
    await expectLater(repository.recover(), throwsA(isA<StateError>()));
    expect(await primary.exists(), isTrue);
    expect(await supportedBackup.exists(), isTrue);
    expect(await supportedTemporary.exists(), isTrue);
  });

  test(
      'does not choose an ambiguous temporary vault without an identity anchor',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    await primary.writeAsString('corrupt primary');
    await File('${primary.path}.bak').writeAsString('corrupt backup');
    await File('${primary.path}.tmp.first').writeAsBytes(
      _document(vaultId: 'first-vault', revision: 2).encode(),
    );
    await File('${primary.path}.tmp.second').writeAsBytes(
      _document(vaultId: 'second-vault', revision: 3).encode(),
    );

    final result = await VaultRepository(directory: directory).inspect();

    expect(result.state, VaultStorageState.corrupt);
    expect(result.document, isNull);
  });

  test('reset deletes primary, backup, temporary, and quarantined artifacts',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    await primary.writeAsBytes(_document().encode());
    await File('${primary.path}.bak').writeAsBytes(_document().encode());
    await File('${primary.path}.tmp.pending')
        .writeAsBytes(_document().encode());
    await File('${primary.path}.corrupt.quarantined')
        .writeAsBytes(_document().encode());

    await VaultRepository(directory: directory).reset(confirmation: 'RESET');

    expect(
      (await directory.list().toList()).whereType<File>(),
      isEmpty,
    );
  });

  test(
      'retains the validated primary and surfaces a recovery candidate when replacement fails',
      () async {
    final primary = File('${directory.path}${Platform.pathSeparator}vault.pwv');
    final original = _document(revision: 1);
    await primary.writeAsBytes(original.encode());
    final repository = VaultRepository(
      directory: directory,
      renameFile: (file, path) {
        if (file.path.contains('.tmp.') && path == primary.path) {
          throw FileSystemException('Synthetic replacement failure');
        }
        return file.rename(path);
      },
    );

    await expectLater(
      repository.save(_document(revision: 2)),
      throwsA(isA<FileSystemException>()),
    );

    final result = await repository.inspect();
    expect(result.state, VaultStorageState.recoveryAvailable);
    expect(result.document!.metadata!.revision, 2);
    expect(
      EncryptedVaultDocument.decode(
        Uint8List.fromList(await primary.readAsBytes()),
      ).metadata!.revision,
      1,
    );
  });
}

Uint8List _unsupportedDocumentBytes() {
  final bytes = _document().encode();
  final decoded =
      String.fromCharCodes(bytes).replaceFirst('"version":2', '"version":999');
  return Uint8List.fromList(decoded.codeUnits);
}

EncryptedVaultDocument _document({
  Uint8List? cipherText,
  String vaultId = 'repository-test',
  int revision = 0,
  bool legacy = false,
}) {
  return EncryptedVaultDocument(
    version: legacy ? legacyVaultDocumentVersion : vaultDocumentVersion,
    kdf: KdfConfig(
      memoryKiB: 64 * 1024,
      iterations: 3,
      parallelism: 1,
      salt: Uint8List(vaultKdfSaltLength),
    ),
    wrappedDek: CipherPayload(
      nonce: Uint8List(xchacha20NonceLength),
      cipherText: Uint8List.fromList([1]),
      mac: Uint8List(poly1305MacLength),
    ),
    payload: CipherPayload(
      nonce: Uint8List(xchacha20NonceLength),
      cipherText: cipherText ?? Uint8List.fromList([1]),
      mac: Uint8List(poly1305MacLength),
    ),
    metadata: legacy
        ? null
        : VaultMetadata(
            vaultId: vaultId,
            keyGeneration: 1,
            revision: revision,
          ),
  );
}
