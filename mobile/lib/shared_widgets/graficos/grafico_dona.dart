import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import 'colores_grafico.dart';

class SegmentoDona {
  const SegmentoDona({
    required this.etiqueta,
    required this.valor,
    required this.color,
    required this.texto,
  });

  final String etiqueta;
  final double valor;
  final Color color;

  /// El valor escrito en la leyenda: `26 %`, `21`.
  final String texto;
}

/// Una dona con su leyenda al lado: cada segmento dice qué es y cuánto vale
/// **en texto**, no solo en color. En el centro, la cifra total.
class GraficoDona extends StatelessWidget {
  const GraficoDona({
    super.key,
    required this.segmentos,
    required this.centroValor,
    required this.centroEtiqueta,
    required this.descripcion,
  });

  final List<SegmentoDona> segmentos;
  final String centroValor;
  final String centroEtiqueta;
  final String descripcion;

  static const _lado = 112.0;
  static const _grosor = 22.0;

  @override
  Widget build(BuildContext context) {
    final conValor = segmentos.where((s) => s.valor > 0).toList();
    final secciones = conValor.isEmpty
        // Sin nada que repartir, un anillo gris en vez de un gráfico roto.
        ? [
            PieChartSectionData(
              value: 1,
              color: ColoresGrafico.rejilla,
              radius: _grosor,
              showTitle: false,
            ),
          ]
        : [
            for (final s in conValor)
              PieChartSectionData(
                value: s.valor,
                color: s.color,
                radius: _grosor,
                showTitle: false,
              ),
          ];

    return Semantics(
      container: true,
      image: true,
      label: 'Gráfico de dona. $descripcion',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _lado,
            height: _lado,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: secciones,
                    sectionsSpace: 0,
                    centerSpaceRadius: _lado / 2 - _grosor,
                    startDegreeOffset: -90,
                    borderData: FlBorderData(show: false),
                    pieTouchData: PieTouchData(enabled: false),
                  ),
                ),
                SizedBox(
                  width: _lado - _grosor * 2 - 8,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          centroValor,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          centroEtiqueta,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppEspacio.md),
          Expanded(
            child: Column(
              children: [
                for (final s in segmentos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        ColoredBox(
                          color: s.color,
                          child: const SizedBox(width: 10, height: 10),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.etiqueta,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.texto,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
