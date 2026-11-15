import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/vault_controller.dart';

final vaultControllerProvider = Provider<VaultController>((ref) {
  throw StateError(
    'vaultControllerProvider must be overridden by the app root.',
  );
});
