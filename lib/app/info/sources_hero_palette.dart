/// Bespoke accent palette for the sources page's hero/credits look.
///
/// These colours have no equivalent role in the app's shared Ocean theme —
/// this page is a credits screen, not part of the product surface — so they
/// are centralised here rather than duplicated as inline hex literals across
/// its widgets.
library;

import 'package:flutter/material.dart';

class SourcesHeroPalette {
  SourcesHeroPalette._();

  static const Color accent = Color(0xFF81cfff);
  static const Color accentContainer = Color(0xFF0079a8);
  static const Color onAccent = Color(0xFF00344b);
  static const Color mutedText = Color(0xFFbfc7d1);
  static const Color cardBackground = Color(0xFF11212e);
  static const Color chipBackground = Color(0xFF263644);
  static const Color licenseItemBackground = Color(0xFF01101b);
  static const Color divider = Color(0x33404850);
}
