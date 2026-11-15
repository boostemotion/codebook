import '../theme/cipherbook_visual_tokens.dart';

abstract final class CategoryWorkbenchTokens {
  static const double railWidth = 200;
  static const double railCompactWidth = 172;
  static const double pageGutter = CipherbookVisualTokens.space16;
  static const double categoryRowHeight =
      CipherbookVisualTokens.mobileControlHeight;
  static const double compactTabHeight = 44;
  static const double compactTabMinWidth = 88;
  static const double navigationClearance = 64;
  static const double touchTargetMin =
      CipherbookVisualTokens.mobileControlHeight;
  static const double controlHeight = CipherbookVisualTokens.controlHeight;
  static const double railBreakpoint = 760;
  static const double detailPaneMinWidth = 232;
  static const double detailPaneMaxWidth = 380;
  static const double categoryFontSize = 13;
  static const double metadataFontSize = 13;
  static const double metadataOpacity = 0.78;
  static const double selectionStripeWidth = 2;

  static const double space4 = CipherbookVisualTokens.space4;
  static const double space8 = CipherbookVisualTokens.space8;
  static const double space12 = CipherbookVisualTokens.space12;
  static const double space16 = CipherbookVisualTokens.space16;
  static const double space20 = CipherbookVisualTokens.space20;
  static const double space24 = CipherbookVisualTokens.space24;
  static const double space32 = CipherbookVisualTokens.space32;

  static const double rowRadius = CipherbookVisualTokens.radiusControl;
  static const double panelRadius = CipherbookVisualTokens.radiusPanel;
  static const double dialogRadius = CipherbookVisualTokens.radiusDialog;

  static const Duration categoryMotion = CipherbookVisualTokens.motionFast;
  static const Duration dragMotion = Duration(milliseconds: 120);
}
