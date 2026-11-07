import 'vault_models.dart';

enum BitwardenExchangeFormat {
  json,
  csv,
}

enum BitwardenImportMatchKind {
  exactDuplicate,
  passwordConflict,
  possibleDuplicate,
}

enum BitwardenImportAction {
  keepBoth,
  useImported,
  keepLocal,
}

class BitwardenImportReview {
  const BitwardenImportReview({
    required this.importedItem,
    required this.localItem,
    required this.kind,
    required this.reason,
    required this.sharedAliases,
    required this.equallyRankedMatchCount,
  });

  final VaultItem importedItem;
  final VaultItem localItem;
  final BitwardenImportMatchKind kind;
  final String reason;
  final List<String> sharedAliases;
  final int equallyRankedMatchCount;

  bool get hasAmbiguousMatches => equallyRankedMatchCount > 1;
}

class BitwardenImportPlan {
  const BitwardenImportPlan({
    required this.sessionGeneration,
    required this.expectedRevision,
    required this.importedItems,
    required this.reviews,
    required this.unsupportedItems,
    required this.reusedPasswordCount,
    required this.warnings,
  });

  final int sessionGeneration;
  final int expectedRevision;
  final List<VaultItem> importedItems;
  final List<BitwardenImportReview> reviews;
  final int unsupportedItems;
  final int reusedPasswordCount;
  final List<String> warnings;

  int get incomingItems => importedItems.length;
}

class BitwardenDeltaExportPlan {
  const BitwardenDeltaExportPlan({
    required this.sessionGeneration,
    required this.expectedRevision,
    required this.baselineItemCount,
    required this.localItemCount,
    required this.matchedItemCount,
    required this.missingItems,
    required this.duplicateCodebookCount,
    required this.unsupportedItems,
    required this.warnings,
  });

  final int sessionGeneration;
  final int expectedRevision;
  final int baselineItemCount;
  final int localItemCount;
  final int matchedItemCount;
  final List<VaultItem> missingItems;
  final int duplicateCodebookCount;
  final int unsupportedItems;
  final List<String> warnings;

  int get missingItemCount => missingItems.length;

  bool get hasMissingItems => missingItems.isNotEmpty;
}
