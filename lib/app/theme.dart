import 'package:flutter/material.dart';

class AppTheme {
  // Miro Signature Design Tokens
  static const Color primaryColor = Color(0xFF0D54FF); // Miro Electric Blue
  static const Color secondaryColor = Color(0xFFFFD02F); // Miro Yellow
  static const Color canvasBackgroundColor = Color(
    0xFFFFFFFF,
  ); // Pure Miro White
  static const Color dotGridColor = Color(0xFFE2E8F0); // Subtle Slate Dot Grid
  static const Color miroDarkText = Color(0xFF050038); // Miro Navy/Ink
  static const Color miroBorder = Color(0xFFE5E7EB); // Subtle Card Border
  static const Color errorColor = Color(0xFFEF4444);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      primary: primaryColor,
      secondary: secondaryColor,
      surface: canvasBackgroundColor,
      error: errorColor,
    ),
    scaffoldBackgroundColor: canvasBackgroundColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: miroDarkText),
      titleTextStyle: TextStyle(
        color: miroDarkText,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: miroBorder),
      ),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      primary: primaryColor,
      secondary: secondaryColor,
      surface: const Color(0xFF1E1E2C),
      error: const Color(0xFFCF6679),
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E2C),
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF2C2C3E),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
