import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tema base de la app. Estilo *flat*: sin sombras, formas rectas, la
/// tipografía como protagonista — como define el design system.
///
/// Pendiente: el design system especifica Fira Sans (UI) y Fira Code (datos).
/// Todavía no están empaquetadas, así que por ahora se usa la fuente del
/// sistema y `monospace` para los datos duros. Al incorporar las fuentes,
/// basta cambiarlo aquí.
abstract final class AppTheme {
  /// Familia monoespaciada para códigos, cantidades y timestamps.
  static const monoFamily = 'monospace';

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accentFill,
        brightness: Brightness.light,
        primary: AppColors.accentFill,
        surface: AppColors.card,
      ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.zero,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentFill,
          foregroundColor: Colors.white,
          // 52 px: por debajo de 44 no se acierta con guantes puestos.
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.primary,
        displayColor: AppColors.primary,
      ),
    );
  }
}
