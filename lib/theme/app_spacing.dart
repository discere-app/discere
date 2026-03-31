import 'package:flutter/widgets.dart';

/// Centralized spacing constants for the app.
/// Follows an 8-point grid system where possible.
class AppSpacing {
  AppSpacing._();

  // --- Base Numeric Constants ---
  static const double s4 = 4.0;
  static const double s8 = 8.0;
  static const double s10 = 10.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s20 = 20.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;
  static const double s48 = 48.0;
  static const double s64 = 64.0;
  static const double s80 = 80.0;

  // --- Semantic Spacings ---
  
  /// Standard screen-edge padding.
  static const double screenPadding = s16;
  
  /// Default padding for interior card contents.
  static const double cardPadding = s12;
  
  /// Default margin between cards or list items.
  static const double cardMargin = s16;
  
  /// Small gap between related elements (e.g., text and icon).
  static const double elementSpacing = s8;
  
  /// Medium gap between sections.
  static const double sectionSpacing = s16;
  
  /// Large gap between logical groups.
  static const double groupSpacing = s24;

  /// Spacing for empty screen messages.
  static const double emptyStatePadding = s32;
  
  /// Standard icon size for empty states.
  static const double emptyStateIconSize = s64;

  // --- EdgeInsets Helpers ---

  /// screenPaddingAll = EdgeInsets.all(16.0)
  static const EdgeInsets screenPaddingAll = EdgeInsets.all(screenPadding);
  
  /// screenPaddingHorizontal = EdgeInsets.symmetric(horizontal: 16.0)
  static const EdgeInsets screenPaddingHorizontal = EdgeInsets.symmetric(horizontal: screenPadding);
  
  /// screenPaddingVertical = EdgeInsets.symmetric(vertical: 8.0)
  static const EdgeInsets screenPaddingVertical = EdgeInsets.symmetric(vertical: s8);

  /// cardPaddingAll = EdgeInsets.all(12.0)
  static const EdgeInsets cardPaddingAll = EdgeInsets.all(cardPadding);

  /// emptyStatePaddingAll = EdgeInsets.all(32.0)
  static const EdgeInsets emptyStatePaddingAll = EdgeInsets.all(emptyStatePadding);

  /// paddingS8All = EdgeInsets.all(8.0)
  static const EdgeInsets paddingS8All = EdgeInsets.all(s8);

  /// paddingS12All = EdgeInsets.all(12.0)
  static const EdgeInsets paddingS12All = EdgeInsets.all(s12);

  /// paddingS16All = EdgeInsets.all(16.0)
  static const EdgeInsets paddingS16All = EdgeInsets.all(s16);

  /// paddingS16Horizontal = EdgeInsets.symmetric(horizontal: 16.0)
  static const EdgeInsets paddingS16Horizontal = EdgeInsets.symmetric(horizontal: s16);

  /// paddingS20All = EdgeInsets.all(20.0)
  static const EdgeInsets paddingS20All = EdgeInsets.all(s20);

  /// paddingS4Horizontal = EdgeInsets.symmetric(horizontal: 4.0)
  static const EdgeInsets paddingS4Horizontal = EdgeInsets.symmetric(horizontal: s4);

  /// paddingS12Vertical = EdgeInsets.symmetric(vertical: 12.0)
  static const EdgeInsets paddingS12Vertical = EdgeInsets.symmetric(vertical: s12);

  /// paddingS4Vertical = EdgeInsets.symmetric(vertical: 4.0)
  static const EdgeInsets paddingS4Vertical = EdgeInsets.symmetric(vertical: s4);

  /// buttonPaddingVertical = EdgeInsets.symmetric(vertical: 16.0)
  static const EdgeInsets buttonPaddingVertical = EdgeInsets.symmetric(vertical: s16);

  // --- SizedBox Helpers (Commonly used gaps) ---
  
  static const Widget heightS4 = SizedBox(height: s4);
  static const Widget heightS8 = SizedBox(height: s8);
  static const Widget heightS12 = SizedBox(height: s12);
  static const Widget heightS16 = SizedBox(height: s16);
  static const Widget heightS24 = SizedBox(height: s24);
  static const Widget heightS32 = SizedBox(height: s32);

  static const Widget widthS4 = SizedBox(width: s4);
  static const Widget widthS8 = SizedBox(width: s8);
  static const Widget widthS12 = SizedBox(width: s12);
  static const Widget widthS16 = SizedBox(width: s16);
  static const Widget widthS24 = SizedBox(width: s24);
}
