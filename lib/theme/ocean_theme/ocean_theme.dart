import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ocean_colors.dart';

final ThemeData oceanTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: OceanColors.primaryBlue,
  scaffoldBackgroundColor: OceanColors.backgroundDark,
  colorScheme: const ColorScheme.dark(
    primary: OceanColors.primaryBlue,
    secondary: OceanColors.secondaryBlue,
    surface: OceanColors.backgroundDark,
    error: OceanColors.error,
    onPrimary: OceanColors.white,
    onSecondary: OceanColors.white,
    onSurface: OceanColors.primaryTextDark,
    onError: OceanColors.white,
  ),

  // App Bar
  appBarTheme: const AppBarTheme(
    backgroundColor: OceanColors.transparent,
    elevation: 0,
    centerTitle: false,
    iconTheme: IconThemeData(color: OceanColors.primaryTextDark),
    titleTextStyle: TextStyle(
      color: OceanColors.primaryTextDark,
      fontSize: 20,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.5, // tight tracking
    ),
  ),

  // Bottom Navigation
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: OceanColors.transparent,
    elevation: 0,
    selectedItemColor: OceanColors.primaryBlue,
    unselectedItemColor: OceanColors.secondaryText,
    showSelectedLabels: true,
    showUnselectedLabels: true,
    type: BottomNavigationBarType.fixed,
    selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
    unselectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
  ),

  // Floating Action Button
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: OceanColors.primaryBlue,
    foregroundColor: OceanColors.white,
    elevation: 4,
    focusElevation: 6,
    hoverElevation: 6,
    highlightElevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(9999),
    ),
  ),

  // Elevated Button
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: OceanColors.primaryBlue,
      foregroundColor: OceanColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w600,
      ),
    ),
  ),

  // Card Theme
  cardTheme: CardThemeData(
    color: OceanColors.elementDarkBackground,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: OceanColors.elementDarkborder),
    ),
  ),

  // Inputs
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: OceanColors.elementDarkBackground,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: OceanColors.elementDarkborder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: OceanColors.elementDarkborder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: OceanColors.primaryBlue),
    ),
    labelStyle: const TextStyle(color: OceanColors.secondaryText),
    hintStyle: const TextStyle(color: OceanColors.secondaryText),
  ),

  // Typography
  textTheme: GoogleFonts.lexendTextTheme(
    ThemeData.dark().textTheme.copyWith(
          displayLarge: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: OceanColors.primaryTextDark,
          ),
          displayMedium: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: OceanColors.primaryTextDark,
          ),
          displaySmall: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: OceanColors.primaryTextDark,
          ),
          headlineMedium: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: OceanColors.primaryTextDark,
          ),
          headlineSmall: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: OceanColors.primaryTextDark,
          ),
          titleLarge: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: OceanColors.primaryTextDark,
          ),
          bodyLarge:
              const TextStyle(fontSize: 14, color: OceanColors.primaryTextDark),
          bodyMedium:
              const TextStyle(fontSize: 14, color: OceanColors.secondaryText),
          bodySmall:
              const TextStyle(fontSize: 12, color: OceanColors.secondaryText),
          titleMedium:
              const TextStyle(fontSize: 14, color: OceanColors.secondaryText),
          titleSmall:
              const TextStyle(fontSize: 12, color: OceanColors.secondaryText),
          labelLarge: const TextStyle(
              fontSize: 14,
              color: OceanColors.white,
              fontWeight: FontWeight.w600),
          labelSmall:
              const TextStyle(fontSize: 10, color: OceanColors.secondaryText),
        ),
  ),
);
