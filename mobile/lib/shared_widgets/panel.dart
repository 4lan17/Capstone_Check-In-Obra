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

/// Panel que se toca. No es `InkWell(child: Panel(...))`: ese envoltorio
/// parece funcionar pero no da ninguna respuesta al tacto, porque el
/// `Container` opaco del `Panel` se dibuja *encima* del splash y lo tapa. El
/// dedo aprieta y no pasa nada visible — que en obra se lee como "la app se
/// colgó" y termina en un segundo toque, es decir, la acción repetida.
///
/// El orden correcto es `Material` (pone el color y recibe el splash) →
/// `InkWell` → contenido con fondo transparente.
class PanelTocable extends StatelessWidget {
  const PanelTocable({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.color = AppColors.card,
    this.borderColor = AppColors.borderControl,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Lo que anuncia el lector de pantalla. Obligatorio: un panel entero
  /// tocable no se describe solo.
  final String semanticLabel;

  final Color color;
  final Color borderColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: Material(
        color: color,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              border: Border.fromBorderSide(BorderSide(color: borderColor)),
            ),
            child: ExcludeSemantics(child: child),
          ),
        ),
      ),
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
    // El design system exige que el chip no quiebre línea. A 10 px, con el
    // texto del sistema al 200 %, "SIN CONEXIÓN" en una sola línea desborda
    // la fila que lo contiene. Se topa el escalado del chip —y solo del
    // chip— en 1.3: sigue creciendo con la preferencia del usuario, pero
    // dentro de lo que la fila aguanta.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
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
    // Las iniciales son una abreviatura decorativa: el nombre completo
    // siempre está escrito al lado. Leerlas en voz alta ("E S") solo agrega
    // ruido antes del dato que sí importa.
    return Container(
      width: tamano,
      height: tamano,
      color: AppColors.primary,
      alignment: Alignment.center,
      child: ExcludeSemantics(
        // El cuadro tiene lado fijo, así que el texto no puede escalar sin
        // desbordarlo.
        child: MediaQuery.withNoTextScaling(
          child: Text(
            de(nombre),
            style: TextStyle(
              fontSize: tamano * 0.32,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
