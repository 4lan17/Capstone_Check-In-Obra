import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'colores_grafico.dart';

/// Una línea del gráfico.
class SerieLinea {
  const SerieLinea({
    required this.nombre,
    required this.valores,
    required this.color,
    this.punteada = false,
    this.conArea = false,
  });

  final String nombre;

  /// Un valor por etiqueta del eje horizontal.
  final List<double> valores;
  final Color color;

  /// Para las series de referencia (el presupuesto): se distinguen de lo real
  /// por el trazo, no solo por el color.
  final bool punteada;

  /// Un área suave debajo: para la serie principal.
  final bool conArea;
}

/// Un gráfico de líneas, de una o varias series, con una referencia punteada
/// opcional. El eje vertical parte de cero y se ajusta para que entren todas.
class GraficoLinea extends StatelessWidget {
  const GraficoLinea({
    super.key,
    required this.etiquetasX,
    required this.series,
    required this.descripcion,
    this.formatoY,
    this.marcaFinal,
    this.alto = 128,
  });

  final List<String> etiquetasX;
  final List<SerieLinea> series;

  /// Lo que lee el lector de pantalla: el gráfico no se puede recorrer punto
  /// por punto, así que se le dice lo importante.
  final String descripcion;

  /// Cómo se escriben los números del eje vertical. Por defecto, enteros.
  final String Function(double)? formatoY;

  /// Si se da, el último punto de la primera serie se marca en rojo y se
  /// escribe esta frase («Supera el presupuesto»): color **y** texto.
  final String? marcaFinal;

  final double alto;

  static const _etiquetasPorEje = 6;

  /// Un paso del eje «redondo»: 1, 2 o 5 por una potencia de diez.
  static double _paso(double maximo) {
    if (maximo <= 0) return 1;
    final bruto = maximo / 4;
    final potencia = math
        .pow(10, (math.log(bruto) / math.ln10).floor())
        .toDouble();
    final f = bruto / potencia;
    final base = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10));
    return base * potencia;
  }

  @override
  Widget build(BuildContext context) {
    final todos = [for (final s in series) ...s.valores];
    final maximo = todos.isEmpty ? 0.0 : todos.reduce(math.max);
    final paso = _paso(maximo);
    final techo = math.max(paso, (maximo / paso).ceil() * paso);
    final n = series.isEmpty
        ? 0
        : series.map((s) => s.valores.length).reduce(math.max);
    final cadaCuantas = n > 7 ? (n / _etiquetasPorEje).ceil() : 1;
    final formato = formatoY ?? (v) => v.toStringAsFixed(0);

    final grafico = LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1, n - 1).toDouble(),
        minY: 0,
        maxY: techo,
        lineTouchData: const LineTouchData(enabled: false),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: paso,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: ColoresGrafico.rejilla, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: paso,
              getTitlesWidget: (valor, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  formato(valor),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: cadaCuantas.toDouble(),
              getTitlesWidget: (valor, meta) {
                final i = valor.round();
                if (valor != i.toDouble() || i < 0 || i >= etiquetasX.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    etiquetasX[i],
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.secondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          for (var k = 0; k < series.length; k++)
            _barra(series[k], resaltarUltimo: k == 0 && marcaFinal != null),
        ],
      ),
    );

    return Semantics(
      container: true,
      image: true,
      label: 'Gráfico de líneas. $descripcion',
      excludeSemantics: true,
      child: SizedBox(
        height: alto,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: grafico,
            ),
            if (marcaFinal != null)
              Positioned(
                right: 10,
                top: 0,
                child: Text(
                  marcaFinal!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: ColoresGrafico.alertaOscura,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _barra(SerieLinea s, {required bool resaltarUltimo}) {
    final ultimo = s.valores.length - 1;
    return LineChartBarData(
      spots: [
        for (var i = 0; i < s.valores.length; i++)
          FlSpot(i.toDouble(), s.valores[i]),
      ],
      isCurved: false,
      color: s.color,
      barWidth: s.conArea ? 2.8 : 2.2,
      isStrokeCapRound: true,
      isStrokeJoinRound: true,
      dashArray: s.punteada ? const [5, 4] : null,
      dotData: FlDotData(
        show: resaltarUltimo,
        checkToShowDot: (spot, _) => spot.x == ultimo,
        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
          radius: 4.5,
          color: ColoresGrafico.alerta,
          strokeWidth: 1.5,
          strokeColor: Colors.white,
        ),
      ),
      belowBarData: BarAreaData(
        show: s.conArea,
        color: s.color.withValues(alpha: 0.10),
      ),
    );
  }
}
