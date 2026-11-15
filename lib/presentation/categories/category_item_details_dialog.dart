import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../models/vault_models.dart';
import '../../state/vault_controller.dart';
import '../shared/password_detail_navigation.dart';
import 'category_item_details_inspector.dart';

Future<void> showCategoryItemDetails({
  required BuildContext context,
  required VaultController controller,
  required VaultItem item,
  required ValueChanged<VaultItem> onSelected,
  ValueChanged<VaultItem>? onEdit,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (routeContext, animation, secondaryAnimation) {
        return _CategoryItemDetailsPage(
          controller: controller,
          item: item,
          onSelected: onSelected,
          onEdit: onEdit,
        );
      },
    ),
  );
}

class _CategoryItemDetailsPage extends StatefulWidget {
  const _CategoryItemDetailsPage({
    required this.controller,
    required this.item,
    required this.onSelected,
    required this.onEdit,
  });

  final VaultController controller;
  final VaultItem item;
  final ValueChanged<VaultItem> onSelected;
  final ValueChanged<VaultItem>? onEdit;

  @override
  State<_CategoryItemDetailsPage> createState() =>
      _CategoryItemDetailsPageState();
}

class _CategoryItemDetailsPageState extends State<_CategoryItemDetailsPage> {
  late VaultItem _item = widget.item;

  void _selectRelated(VaultItem item) {
    if (item.id == _item.id) {
      return;
    }
    setState(() {
      _item = item;
    });
    widget.onSelected(item);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ColoredBox(
      key: const ValueKey('prism-category-detail-page'),
      color: colorScheme.surface,
      child: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordDetailNavigation(
              backButtonKey: const ValueKey('prism-category-detail-back'),
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: PasswordDetailFrame(
                child: CategoryItemDetailsInspector(
                  key: ValueKey('prism-category-detail-${_item.id}'),
                  controller: widget.controller,
                  item: _item,
                  onSelectItem: _selectRelated,
                  onEdit: widget.onEdit == null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          widget.onEdit!(_item);
                        },
                  onMoved: () {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
