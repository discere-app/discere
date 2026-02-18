import 'package:flutter/material.dart';

class MarineColors {
  // Hauptfarben
  static const Color primaryBlue = Color(0xFF004777);
  static const Color primaryRed = Color(0xFFA30000);
  static const Color primaryOrange = Color(0xFFFF7700);
  static const Color primaryYellow = Color(0xFFEFD28D);
  static const Color primaryPurple = Color(0xFF7E1946);
  static const Color primaryTeal = Color(0xFF00AFB5);
  static const Color white = Color(0xFFFFFFFF);

  // Zusätzliche Farben (für bessere UX und UI)
  static const Color black = Color(0xFF000000);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFEEEEEE);
  static const Color grey300 = Color(0xFFE0E0E0);
  static const Color grey400 = Color(0xFFBDBDBD);
  static const Color grey500 = Color(0xFF9E9E9E);
  static const Color grey600 = Color(0xFF757575);
  static const Color grey700 = Color(0xFF616161);
  static const Color grey800 = Color(0xFF424242);
  static const Color grey900 = Color(0xFF212121);
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFF44336);
  static const Color warning = Color(0xFFFFC107);
  static const Color info = Color(0xFF2196F3);

  // Farbverläufe (optional)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlue, primaryTeal],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Textfarben (für bessere Lesbarkeit)
  static const Color primaryText = black;
  static const Color secondaryText = grey700;
  static const Color lightText = white;
}
