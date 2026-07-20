import 'package:flutter/material.dart';

extension ColorContrastExtension on Color {
  /// Black or white, whichever reads more clearly on top of this color.
  Color get onColor => computeLuminance() > 0.5 ? Colors.black : Colors.white;
}
