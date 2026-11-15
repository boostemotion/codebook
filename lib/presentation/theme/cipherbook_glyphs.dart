import 'dart:math' as math;

import 'package:prism_ui/icons/glyph.dart';

abstract final class VaultGlyphs {
  static const add = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 5),
      GlyphVertex(12, 19),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5, 12),
      GlyphVertex(19, 12),
    ], role: GlyphRole.line),
  ]);

  static const dashboard = Glyph([
    GlyphBox(3.5, 3.5, 10.5, 11.5, 2),
    GlyphBox(13.5, 3.5, 20.5, 9.5, 2),
    GlyphBox(3.5, 14.5, 10.5, 20.5, 2),
    GlyphBox(13.5, 12.5, 20.5, 20.5, 2),
  ]);

  static const vault = Glyph([
    GlyphBox(3.5, 9.5, 20.5, 21, 3),
    GlyphPolyline([
      GlyphVertex(7, 9.5),
      GlyphVertex(7, 6.8, 3.8),
      GlyphVertex(17, 6.8, 3.8),
      GlyphVertex(17, 9.5),
    ], role: GlyphRole.line),
    GlyphCircle(12, 15.3, 1.4, role: GlyphRole.detail, solid: true),
  ]);

  static const categories = Glyph([
    GlyphBox(3, 3.5, 21, 8.5, 1.8),
    GlyphBox(4.5, 10.8, 19.5, 20.5, 2.2),
    GlyphPolyline([
      GlyphVertex(9.4, 14.4),
      GlyphVertex(14.6, 14.4),
    ], role: GlyphRole.detail),
  ]);

  static const shield = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 3.2),
      GlyphVertex(20, 6.5),
      GlyphVertex(18.4, 14.4, 2),
      GlyphVertex(12, 21),
      GlyphVertex(5.6, 14.4, 2),
      GlyphVertex(4, 6.5),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(8.1, 12.2),
      GlyphVertex(11, 15, 0.5),
      GlyphVertex(16.2, 9.3, 0.5),
    ], role: GlyphRole.detail),
  ]);

  static const favorite = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 3),
      GlyphVertex(14.7, 8.55, 0.5),
      GlyphVertex(20.8, 9.45, 0.5),
      GlyphVertex(16.4, 13.75, 0.5),
      GlyphVertex(17.45, 19.85),
      GlyphVertex(12, 17, 0.5),
      GlyphVertex(6.55, 19.85),
      GlyphVertex(7.6, 13.75, 0.5),
      GlyphVertex(3.2, 9.45, 0.5),
      GlyphVertex(9.3, 8.55, 0.5),
    ], closed: true),
  ]);

  static const sync = Glyph([
    GlyphArc(
      12,
      12,
      7.78,
      math.pi * 1.144,
      math.pi * 0.889,
      role: GlyphRole.line,
    ),
    GlyphPolyline([
      GlyphVertex(5, 5),
      GlyphVertex(5, 8.6, 0.4),
      GlyphVertex(8.6, 8.6),
    ], role: GlyphRole.line),
    GlyphArc(
      12,
      12,
      7.78,
      math.pi * 0.144,
      math.pi * 0.889,
      role: GlyphRole.line,
    ),
    GlyphPolyline([
      GlyphVertex(19, 19),
      GlyphVertex(19, 15.4, 0.4),
      GlyphVertex(15.4, 15.4),
    ], role: GlyphRole.line),
  ]);

  static const tools = Glyph([
    GlyphBox(3, 7, 21, 20, 2.8),
    GlyphPolyline([
      GlyphVertex(9, 7),
      GlyphVertex(9, 4.6, 1.4),
      GlyphVertex(15, 4.6, 1.4),
      GlyphVertex(15, 7),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(3.2, 12.6),
      GlyphVertex(9.6, 12.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(14.4, 12.6),
      GlyphVertex(20.8, 12.6),
    ], role: GlyphRole.detail),
    GlyphBox(10.4, 11, 13.6, 14.4, 1, role: GlyphRole.detail),
  ]);

  static const edit = Glyph([
    GlyphPolyline([
      GlyphVertex(4.5, 19.5),
      GlyphVertex(5.3, 15.2),
      GlyphVertex(15.8, 4.7, 1.2),
      GlyphVertex(19.3, 8.2, 1.2),
      GlyphVertex(8.8, 18.7),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(13.9, 6.6),
      GlyphVertex(17.4, 10.1),
    ], role: GlyphRole.detail),
  ]);

  static const delete = Glyph([
    GlyphBox(6, 7, 18, 20.5, 2.2),
    GlyphPolyline([
      GlyphVertex(4, 7),
      GlyphVertex(20, 7),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9, 7),
      GlyphVertex(9, 4.2, 1.4),
      GlyphVertex(15, 4.2, 1.4),
      GlyphVertex(15, 7),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(10, 10.5),
      GlyphVertex(10, 17),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(14, 10.5),
      GlyphVertex(14, 17),
    ], role: GlyphRole.detail),
  ]);
}
