import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// La paleta de los gráficos, sacada de los tokens del tema y de la lámina
/// «Gráficos» del diseño. Los colores significan siempre lo mismo:
/// **naranja = lo ejecutado o real**, gris claro = lo presupuestado, gris
/// azulado = una referencia, y **rojo = por sobre el umbral**.
///
/// El color nunca va solo: cada gráfico dice lo mismo en texto (etiquetas,
/// leyenda, cifras), porque quien no distingue colores —o el sol de la obra—
/// no puede depender de él.
abstract final class ColoresGrafico {
  /// Lo ejecutado, lo real, lo que se mira.
  static const ejecutado = AppColors.accent;

  /// Lo presupuestado, el punto de comparación.
  static const presupuesto = Color(0xFFCBD5E1);

  /// Una serie de referencia (la línea punteada).
  static const referencia = AppColors.secondary;

  /// El gris oscuro de los rankings y de las categorías neutras.
  static const neutro = AppColors.primary;
  static const neutroMedio = AppColors.textMuted;

  /// Sobre el umbral. [alertaOscura] es para texto sobre fondo claro.
  static const alerta = AppColors.destructive;
  static const alertaOscura = AppColors.destructiveDark;

  /// Las rejillas y ejes tenues.
  static const rejilla = AppColors.border;

  /// El gris azulado claro de las categorías menores.
  static const gris = AppColors.textFaint;

  /// «Otros»: lo que no cabe en las categorías con nombre. Siempre el más
  /// tenue, para que no compita con ellas.
  static const otros = AppColors.border;

  /// Los colores de las categorías de una dona, en orden: el primero es el
  /// que más pesa.
  static const categoricos = <Color>[ejecutado, neutro, referencia, gris];
}
