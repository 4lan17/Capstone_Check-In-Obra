import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../panel.dart';
import 'colores_grafico.dart';

/// Cómo se dibuja un ítem de la leyenda: igual que lo que representa.
enum EstiloLeyenda { cuadro, linea, lineaPunteada }

class ItemLeyenda {
  const ItemLeyenda({
    required this.etiqueta,
    required this.color,
    this.estilo = EstiloLeyenda.cuadro,
  });

  final String etiqueta;
  final Color color;
  final EstiloLeyenda estilo;
}

/// La tarjeta de una métrica: título, una cifra grande con su explicación, el
/// gráfico y su leyenda. Es la misma para los tres roles.
class TarjetaMetrica extends StatelessWidget {
  const TarjetaMetrica({
    super.key,
    required this.titulo,
    required this.child,
    this.cifra,
    this.detalle,
    this.colorCifra = ColoresGrafico.neutro,
    this.leyenda = const [],
  });

  final String titulo;

  /// La cifra que resume el gráfico: es lo primero que se lee.
  final String? cifra;
  final String? detalle;
  final Color colorCifra;
  final Widget child;
  final List<ItemLeyenda> leyenda;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(titulo, style: AppTexto.rotulo)),
          if (cifra != null || detalle != null) ...[
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                if (cifra != null)
                  Text(
                    cifra!,
                    style: TextStyle(
                      fontFamily: AppTheme.monoFamily,
                      fontSize: 20,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: colorCifra,
                    ),
                  ),
                if (detalle != null)
                  Text(
                    detalle!,
                    style: AppTexto.cuerpoChico.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          child,
          if (leyenda.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [for (final i in leyenda) _Leyenda(item: i)],
            ),
          ],
        ],
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.item});

  final ItemLeyenda item;

  @override
  Widget build(BuildContext context) {
    final muestra = switch (item.estilo) {
      EstiloLeyenda.cuadro => ColoredBox(
        color: item.color,
        child: const SizedBox(width: 10, height: 10),
      ),
      EstiloLeyenda.linea => ColoredBox(
        color: item.color,
        child: const SizedBox(width: 20, height: 3),
      ),
      EstiloLeyenda.lineaPunteada => CustomPaint(
        size: const Size(20, 8),
        painter: _PintorDeLineaPunteada(item.color),
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: muestra),
        const SizedBox(width: 6),
        Text(
          item.etiqueta,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _PintorDeLineaPunteada extends CustomPainter {
  const _PintorDeLineaPunteada(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = 2.2;
    final y = size.height / 2;
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + 4).clamp(0, size.width), y),
        pincel,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorDeLineaPunteada anterior) =>
      anterior.color != color;
}
