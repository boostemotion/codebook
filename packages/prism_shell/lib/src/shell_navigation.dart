import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShellDestinationController extends Notifier<String> {
  @override
  String build() => '';

  void go(String destinationId) {
    state = destinationId;
  }
}

/// The active top-level destination shared by shell hosts and tests.
///
/// An empty value means "use the ResponsiveShell's initial destination".
final currentShellDestinationProvider =
    NotifierProvider<ShellDestinationController, String>(
      ShellDestinationController.new,
    );

typedef ShellSelectDestination = void Function(String destinationId);
typedef ShellPushDestination =
    Future<void> Function(BuildContext context, String destinationId);

class ShellNavigation {
  const ShellNavigation({required this.select, required this.push});

  final ShellSelectDestination select;
  final ShellPushDestination push;
}

/// Lets retained pages select or push shell destinations without importing the
/// concrete shell, its destination list, or a product-specific page enum.
class ShellNavigationScope extends InheritedWidget {
  const ShellNavigationScope({
    super.key,
    required this.navigation,
    required super.child,
  });

  final ShellNavigation navigation;

  static ShellNavigationScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShellNavigationScope>();
    assert(scope != null, 'No ShellNavigationScope found in context.');
    return scope!;
  }

  static ShellNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellNavigationScope>();
  }

  static ShellNavigation navigationOf(BuildContext context) {
    return of(context).navigation;
  }

  @override
  bool updateShouldNotify(ShellNavigationScope oldWidget) {
    return navigation != oldWidget.navigation;
  }
}
