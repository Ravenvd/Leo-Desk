import 'package:flutter/material.dart';

/// Leo Desk 2.0 design system.
///
/// Palette is derived from the Leo Stitch & Design logo:
/// warm ivory, deep espresso, muted taupe, and champagne.
abstract final class AppColors {
  static const warmIvory = Color(0xFFFAF7F0);
  static const softCream = Color(0xFFF3EEE5);

  static const deepEspresso = Color(0xFF5F584E);
  static const darkEspresso = Color(0xFF403B35);

  static const mutedTaupe = Color(0xFF9A8F80);
  static const champagne = Color(0xFFB7AA98);

  static const warmGreige = Color(0xFFD8D0C4);
  static const softGreige = Color(0xFFE5DED3);

  static const primaryText = Color(0xFF3F3A34);
  static const secondaryText = Color(0xFF756E65);

  static const success = Color(0xFF5F765F);
  static const warning = Color(0xFF9A7B4F);
  static const error = Color(0xFF9A5E57);
  static const info = Color(0xFF687A82);
}

abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.light(
      primary: AppColors.deepEspresso,
      onPrimary: AppColors.warmIvory,
      primaryContainer: AppColors.softGreige,
      onPrimaryContainer: AppColors.darkEspresso,
      secondary: AppColors.mutedTaupe,
      onSecondary: AppColors.warmIvory,
      secondaryContainer: AppColors.softCream,
      onSecondaryContainer: AppColors.darkEspresso,
      tertiary: AppColors.champagne,
      onTertiary: AppColors.darkEspresso,
      tertiaryContainer: AppColors.softCream,
      onTertiaryContainer: AppColors.darkEspresso,
      surface: AppColors.warmIvory,
      onSurface: AppColors.primaryText,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.softCream,
      surfaceContainer: AppColors.softCream,
      surfaceContainerHigh: AppColors.softGreige,
      surfaceContainerHighest: AppColors.warmGreige,
      outline: AppColors.warmGreige,
      outlineVariant: AppColors.softGreige,
      error: AppColors.error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.warmIvory,

      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.primaryText),
        bodyMedium: TextStyle(color: AppColors.primaryText),
        bodySmall: TextStyle(color: AppColors.secondaryText),
        titleLarge: TextStyle(
          color: AppColors.darkEspresso,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: AppColors.primaryText,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: TextStyle(
          color: AppColors.primaryText,
          fontWeight: FontWeight.w600,
        ),
        headlineLarge: TextStyle(
          color: AppColors.darkEspresso,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          color: AppColors.darkEspresso,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: TextStyle(
          color: AppColors.darkEspresso,
          fontWeight: FontWeight.w700,
        ),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.warmIvory,
        foregroundColor: AppColors.darkEspresso,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),

      cardTheme: const CardThemeData(
        color: AppColors.softCream,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.warmGreige,
        thickness: 1,
        space: 1,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.warmGreige),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.warmGreige),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.deepEspresso,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.deepEspresso,
          foregroundColor: AppColors.warmIvory,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.deepEspresso,
          foregroundColor: AppColors.warmIvory,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.deepEspresso,
          side: const BorderSide(color: AppColors.warmGreige),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.deepEspresso,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.deepEspresso,
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: AppColors.secondaryText,
        textColor: AppColors.primaryText,
        selectedColor: AppColors.deepEspresso,
        selectedTileColor: AppColors.softGreige,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: AppColors.softCream,
        indicatorColor: AppColors.softGreige,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.softGreige,
        selectedColor: AppColors.deepEspresso,
        secondarySelectedColor: AppColors.deepEspresso,
        side: const BorderSide(color: AppColors.warmGreige),
        labelStyle: const TextStyle(color: AppColors.primaryText),
        secondaryLabelStyle: const TextStyle(color: AppColors.warmIvory),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.warmIvory,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkEspresso,
        contentTextStyle: const TextStyle(color: AppColors.warmIvory),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.deepEspresso,
        foregroundColor: AppColors.warmIvory,
        elevation: 2,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.darkEspresso,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: AppColors.warmIvory),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.deepEspresso,
      ),
    );
  }
}
