import 'package:flutter/material.dart';

/// Paleta de Check-In-Obra — los valores salen tal cual de
/// `docs/design-system/Check-In-Obra_Design_System.md`.
///
/// Sobre el naranjo: el catálogo define `#EA580C` como acento, pero sobre
/// blanco mide 3.56:1 y no pasa el 4.5:1 que exige el propio checklist del
/// design system. Por eso el acento se reserva para íconos y marcas, y el
/// relleno de botón primario usa `#C2410C` (5.1:1).
abstract final class AppColors {
  static const primary = Color(0xFF334155);
  static const secondary = Color(0xFF64748B);

  /// Acento — solo íconos, marcas de gráfico y foco.
  static const accent = Color(0xFFEA580C);

  /// Relleno de botón primario — versión con contraste suficiente.
  static const accentFill = Color(0xFFC2410C);

  static const background = Color(0xFFF8FAFC);
  static const card = Color(0xFFFFFFFF);

  /// Separador decorativo entre superficies. Mide 1.2:1 y con eso basta:
  /// no identifica ningún control, solo agrupa.
  static const border = Color(0xFFE2E8F0);

  /// Borde de un control — campo de texto, tecla, panel que se toca.
  /// Mide 3.3:1 sobre el relleno de los campos, por encima del 3:1 que
  /// exige WCAG para el contorno que identifica un componente. El `border`
  /// decorativo no sirve acá: sobre el relleno queda en 1.2:1 y el campo
  /// parece un bloque de texto, no algo donde escribir.
  static const borderControl = Color(0xFF7E8CA0);

  /// Semáforo. Se usan como chip tintado (fondo claro + texto oscuro),
  /// nunca como texto de color puro sobre blanco.
  static const success = Color(0xFF059669);
  static const successDark = Color(0xFF047857);
  static const successTint = Color(0xFFECFDF5);

  static const warning = Color(0xFFD97706);
  static const warningDark = Color(0xFFB45309);
  static const warningTint = Color(0xFFFFFBEB);

  static const destructive = Color(0xFFDC2626);
  static const destructiveDark = Color(0xFFB91C1C);
  static const destructiveTint = Color(0xFFFEF2F2);

  static const textMuted = Color(0xFF475569);

  /// Texto y bordes tenues **sobre fondo claro**. Mide 2.6:1 sobre blanco,
  /// así que no se usa para texto: solo para íconos decorativos que
  /// acompañan a un texto que ya dice lo mismo.
  static const textFaint = Color(0xFF94A3B8);

  /// Texto secundario **sobre las superficies oscuras** (`primary` y el
  /// panel `surfaceDark`). Mide 7:1 sobre `primary`; `textFaint` ahí se
  /// quedaba en 4:1 y no pasaba el 4.5:1 del propio design system.
  static const textOnDark = Color(0xFFCBD5E1);

  /// Panel oscuro sobre el encabezado, y su borde.
  static const surfaceDark = Color(0xFF1E293B);
  static const borderOnDark = Color(0xFF64748B);
}
