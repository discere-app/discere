import 'package:flutter/material.dart';

import 'marine_colors.dart';

final ThemeData marineTheme = ThemeData(
  // Primäre Farben
  primaryColor: MarineColors.primaryBlue,
  scaffoldBackgroundColor: MarineColors.grey100,

  // AppBar-Design
  appBarTheme: const AppBarTheme(
    backgroundColor: MarineColors.primaryBlue,
    iconTheme: IconThemeData(color: MarineColors.white),
    titleTextStyle: TextStyle(
      color: MarineColors.white,
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: MarineColors.primaryBlue,
    selectedItemColor: MarineColors.grey100,
    unselectedItemColor: MarineColors.white,
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: MarineColors.primaryPurple,
      foregroundColor: MarineColors.white,
    ),
  ),
  // FloatingActionButton Theme
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: MarineColors
        .primaryPurple, // Verwenden Sie die Sekundärfarbe für den Hintergrund
    foregroundColor: MarineColors.white, // Verwenden Sie Weiß für das Symbol
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10.0),
    ), // Optionale runde Ecken
  ),
  // TextTheme
  textTheme: const TextTheme(
    displayLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.bold,
      color: MarineColors.primaryText,
    ),
    displayMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: MarineColors.primaryText,
    ),
    displaySmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: MarineColors.primaryText,
    ),
    headlineMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: MarineColors.primaryText,
    ),
    headlineSmall: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: MarineColors.primaryText,
    ),
    titleLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: MarineColors.primaryText,
    ),
    bodyLarge: TextStyle(fontSize: 14, color: MarineColors.primaryText),
    bodyMedium: TextStyle(fontSize: 12, color: MarineColors.secondaryText),
    titleMedium: TextStyle(fontSize: 14, color: MarineColors.secondaryText),
    titleSmall: TextStyle(fontSize: 12, color: MarineColors.secondaryText),
    labelLarge: TextStyle(fontSize: 14, color: MarineColors.white),
    bodySmall: TextStyle(fontSize: 12, color: MarineColors.grey700),
    labelSmall: TextStyle(fontSize: 10, color: MarineColors.grey700),
  ),

  // ColorScheme
  colorScheme: ColorScheme.fromSwatch().copyWith(
    primary: MarineColors.primaryBlue,
    secondary: MarineColors.primaryPurple,
    surface: MarineColors.white,
    error: MarineColors.error,
    onPrimary: MarineColors.white,
    onSecondary: MarineColors.white,
    onSurface: MarineColors.black,
    onError: MarineColors.white,
    errorContainer: MarineColors.primaryRed,
  ),
);
