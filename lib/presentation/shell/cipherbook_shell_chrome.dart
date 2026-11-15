import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract final class CipherbookDetailLayout {
  /// Matches the previous 760px content breakpoint with the compact app rail.
  static const double listDetailBreakpoint = 824;

  static bool usesListDetail(BuildContext context) {
    return MediaQuery.sizeOf(context).width < listDetailBreakpoint;
  }
}

final passwordDetailShellHiddenProvider =
    NotifierProvider<PasswordDetailShellHiddenController, bool>(
      PasswordDetailShellHiddenController.new,
    );

class PasswordDetailShellHiddenController extends Notifier<bool> {
  @override
  bool build() => false;

  void setHidden(bool hidden) {
    if (state != hidden) {
      state = hidden;
    }
  }
}
