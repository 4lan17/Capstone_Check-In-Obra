import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tema base de la app. Estilo *flat*: sin sombras, formas rectas, la
/// tipografía como protagonista — como define el design system.
///
/// Hay un solo tema y es claro. No es un olvido: la app se usa a pleno sol
/// sobre andamios, donde el fondo claro con texto oscuro es lo que se lee, y
/// `MaterialApp` la fija con `themeMode: ThemeMode.light` para que el modo
/// oscuro del sistema no la arrastre a una paleta que nadie verificó. Si en
/// algún momento hay turno de noche, el tema oscuro se agrega acá y hay que
/// medirle el contraste por separado — los valores del claro no se heredan.
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
      // Los campos de texto de toda la app heredan de acá, para que el
      // contorno que los identifica no dependa de que cada pantalla se
      // acuerde de pasar el color correcto.
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.borderControl),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.borderControl),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.destructive),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.destructive, width: 2),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.primary,
        displayColor: AppColors.primary,
      ),
    );
  }
}
