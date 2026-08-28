import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Superficie base del sistema: rectángulo con borde de 1 px, sin sombra ni
/// esquinas redondeadas. Es el estilo *flat* que define el design system.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color = AppColors.card,
    this.borderColor = AppColors.border,
    this.padding = const EdgeInsets.all(14),
    this.borderIzquierdo,
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final EdgeInsets padding;

  /// Franja de color a la izquierda, para marcar criticidad en listas
  /// (rojo = vencido, ámbar = por vencer, verde = al día).
  final Color? borderIzquierdo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border(
          top: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor),
          left: borderIzquierdo != null
              ? BorderSide(color: borderIzquierdo!, width: 3)
              : BorderSide(color: borderColor),
        ),
      ),
      child: child,
    );
  }
}

/// Rótulo de sección: mayúsculas, pequeño y espaciado.
class Etiqueta extends StatelessWidget {
  const Etiqueta(this.texto, {super.key, this.color = AppColors.textMuted});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: color,
      ),
    );
  }
}

/// Chip de estado tintado. Nunca texto de color puro sobre blanco: siempre
/// fondo claro con el texto en su paso oscuro, para cumplir el 4.5:1.
class ChipEstado extends StatelessWidget {
  const ChipEstado({
    super.key,
    required this.texto,
    required this.fondo,
    required this.textoColor,
    this.punto,
  });

  /// Verde — a tiempo, disponible, aprobada.
  factory ChipEstado.exito(String texto, {bool conPunto = true}) => ChipEstado(
    texto: texto,
    fondo: AppColors.successTint,
    textoColor: AppColors.successDark,
    punto: conPunto ? AppColors.success : null,
  );

  /// Ámbar — por vencer, pendiente, en mantención.
  factory ChipEstado.aviso(String texto, {bool conPunto = true}) => ChipEstado(
    texto: texto,
    fondo: AppColors.warningTint,
    textoColor: AppColors.warningDark,
    punto: conPunto ? AppColors.warning : null,
  );

  /// Rojo — vencido, stock crítico, rechazada.
  factory ChipEstado.critico(String texto, {bool conPunto = true}) =>
      ChipEstado(
        texto: texto,
        fondo: AppColors.destructiveTint,
        textoColor: AppColors.destructiveDark,
        punto: conPunto ? AppColors.destructive : null,
      );

  /// Gris — neutro, entregada, cerrada.
  factory ChipEstado.neutro(String texto) => ChipEstado(
    texto: texto,
    fondo: const Color(0xFFF1F5F9),
    textoColor: AppColors.textMuted,
  );

  final String texto;
  final Color fondo;
  final Color textoColor;
  final Color? punto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      color: fondo,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (punto != null) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: punto, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            texto.toUpperCase(),
            // El chip nunca quiebra línea: el ancho se adapta al texto.
            softWrap: false,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textoColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Iniciales sobre cuadro sólido — el "avatar" del sistema.
class Iniciales extends StatelessWidget {
  const Iniciales(this.nombre, {super.key, this.tamano = 44});

  final String nombre;
  final double tamano;

  static String de(String nombre) {
    final partes = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) {
      return partes.first.substring(0, 1).toUpperCase();
    }
    return (partes[0].substring(0, 1) + partes[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      color: AppColors.primary,
      alignment: Alignment.center,
      child: Text(
        de(nombre),
        style: TextStyle(
          fontSize: tamano * 0.32,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
