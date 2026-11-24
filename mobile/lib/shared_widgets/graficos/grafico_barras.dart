import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'colores_grafico.dart';

/// Una barra de un grupo: su valor decide el largo; el texto es lo que se lee.
class BarraDeGrupo {
  const BarraDeGrupo({
    required this.valor,
    required this.color,
    required this.texto,
  });

  final double valor;
  final Color color;

  /// El valor escrito, al final de la barra: `$13,5 M`, `142 pl`.
  final String texto;
}

class GrupoDeBarras {
  const GrupoDeBarras({
    required this.etiqueta,
    required this.barras,
    required this.descripcion,
  });

  final String etiqueta;
  final List<BarraDeGrupo> barras;

  /// Lo que dice el lector de pantalla de este grupo, con todas sus cifras.
  final String descripcion;
}

/// Barras horizontales agrupadas: cada grupo tiene su etiqueta a la izquierda
/// y una o más barras. Con una sola barra por grupo sirve de ranking.
///
/// Todas las barras comparten escala: el largo es proporcional al valor, y la
/// más larga llega hasta donde se alcanza a escribir su cifra.
class GraficoBarrasAgrupadas extends StatelessWidget {
  const GraficoBarrasAgrupadas({
    super.key,
    required this.grupos,
    required this.descripcion,
  });

  final List<GrupoDeBarras> grupos;
  final String descripcion;

  static const _alturaDeBarra = 10.0;
  static const _separacionDeBarras = 3.0;

  @override
  Widget build(BuildContext context) {
    final escala = MediaQuery.textScalerOf(context);
    final anchoEtiqueta = escala.scale(88);
    final anchoValor = escala.scale(66);
    final maximo = grupos
        .expand((g) => g.barras)
        .fold<double>(0, (m, b) => math.max(m, b.valor));

    return Semantics(
      container: true,
      label: 'Gráfico de barras. $descripcion',
      child: LayoutBuilder(
        builder: (context, c) {
          final largoMaximo = math.max(
            0.0,
            c.maxWidth - anchoEtiqueta - anchoValor - 6,
          );
          return Column(
            children: [
              for (final g in grupos)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Semantics(
                    container: true,
                    label: g.descripcion,
                    excludeSemantics: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: anchoEtiqueta,
                          child: Text(
                            g.etiqueta,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < g.barras.length; i++) ...[
                                if (i > 0)
                                  const SizedBox(height: _separacionDeBarras),
                                _Barra(
                                  llave: ValueKey('barra-${g.etiqueta}-$i'),
                                  barra: g.barras[i],
                                  largo: maximo <= 0
                                      ? 0
                                      : g.barras[i].valor /
                                            maximo *
                                            largoMaximo,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.llave, required this.barra, required this.largo});

  final Key llave;
  final BarraDeGrupo barra;
  final double largo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          key: llave,
          width: barra.valor > 0 ? math.max(2.0, largo) : 0,
          height: GraficoBarrasAgrupadas._alturaDeBarra,
          child: ColoredBox(color: barra.color),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            barra.texto,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Una barra de [GraficoBarrasDivergentes]: sale del cero hacia la derecha si
/// es positiva y hacia la izquierda si es negativa. Sin [valor] (por ejemplo,
/// una obra sin presupuesto) no se dibuja barra, pero la fila sigue ahí y lo
/// dice con su [texto].
class BarraDivergente {
  const BarraDivergente({
    required this.etiqueta,
    required this.valor,
    required this.color,
    required this.texto,
    this.descripcion,
  });

  final String etiqueta;
  final double? valor;
  final Color color;
  final String texto;

  /// Lo que lee el lector de pantalla; si falta, «etiqueta: texto».
  final String? descripcion;
}

/// Barras horizontales que parten de un eje en cero, con una línea de umbral
/// punteada: se ve de un golpe qué se pasa, qué no y por cuánto.
class GraficoBarrasDivergentes extends StatelessWidget {
  const GraficoBarrasDivergentes({
    super.key,
    required this.barras,
    required this.descripcion,
    this.umbral,
    this.etiquetaUmbral,
  });

  final List<BarraDivergente> barras;
  final String descripcion;

  /// Dónde cae la línea punteada, en las mismas unidades que los valores.
  final double? umbral;
  final String? etiquetaUmbral;

  static const _altoDeBarra = 14.0;

  @override
  Widget build(BuildContext context) {
    final escala = MediaQuery.textScalerOf(context);
    final anchoValor = escala.scale(70);
    // Dos líneas de etiqueta (los nombres de obra son largos) y un respiro:
    // si la fila fuera más baja, la etiqueta pisaría a la de abajo.
    final altoDeFila = math.max(34.0, escala.scale(11.5) * 1.3 * 2 + 8);
    final valores = [
      for (final b in barras)
        if (b.valor != null) b.valor!,
    ];
    final minimo = math.min(0.0, valores.fold<double>(0, math.min));
    var maximo = math.max(
      math.max(0.0, valores.fold<double>(0, math.max)),
      umbral ?? 0,
    );
    if (maximo - minimo <= 0) maximo = minimo + 1;
    final alto = barras.length * altoDeFila + (umbral != null ? 24 : 0);

    return Semantics(
      container: true,
      label: 'Gráfico de barras. $descripcion',
      child: LayoutBuilder(
        builder: (context, c) {
          // La etiqueta tiene un tercio del ancho: lo bastante para un nombre
          // de obra en dos líneas, sin quitarle espacio a las barras.
          final anchoEtiqueta = (c.maxWidth * 0.34).clamp(88.0, 150.0);
          final inicio = anchoEtiqueta + 8;
          final area = math.max(1.0, c.maxWidth - inicio - anchoValor);
          final porUnidad = area / (maximo - minimo);
          final cero = inicio + (-minimo) * porUnidad;

          return SizedBox(
            height: alto,
            child: Stack(
              children: [
                // El eje en cero y, si hay, el umbral, detrás de las barras.
                Positioned(
                  key: const ValueKey('eje-cero'),
                  left: cero,
                  top: 0,
                  width: 1,
                  height: barras.length * altoDeFila,
                  child: const ColoredBox(color: AppColors.borderControl),
                ),
                if (umbral != null)
                  Positioned(
                    key: const ValueKey('linea-umbral'),
                    left: cero + umbral! * porUnidad - 1,
                    top: 0,
                    width: 2,
                    height: barras.length * altoDeFila,
                    child: CustomPaint(painter: _PintorDelUmbral()),
                  ),
                for (var i = 0; i < barras.length; i++)
                  _Fila(
                    barra: barras[i],
                    arriba: i * altoDeFila,
                    alto: altoDeFila,
                    anchoEtiqueta: anchoEtiqueta,
                    cero: cero,
                    porUnidad: porUnidad,
                  ),
                if (umbral != null && etiquetaUmbral != null)
                  Positioned(
                    left: cero + umbral! * porUnidad - 40,
                    width: 80,
                    top: barras.length * altoDeFila + 4,
                    child: Text(
                      etiquetaUmbral!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.barra,
    required this.arriba,
    required this.alto,
    required this.anchoEtiqueta,
    required this.cero,
    required this.porUnidad,
  });

  final BarraDivergente barra;
  final double arriba;
  final double alto;
  final double anchoEtiqueta;
  final double cero;
  final double porUnidad;

  @override
  Widget build(BuildContext context) {
    final v = barra.valor;
    final largo = v == null ? 0.0 : (v.abs() * porUnidad);
    final izquierda = v == null || v >= 0 ? cero : cero + v * porUnidad;
    // El valor escrito va pegado al final de la barra; si es negativa o no hay
    // barra, justo a la derecha del cero.
    final textoEn = (v != null && v > 0) ? cero + largo + 6 : cero + 6;

    return Positioned(
      left: 0,
      right: 0,
      top: arriba,
      height: alto,
      child: Semantics(
        container: true,
        label: barra.descripcion ?? '${barra.etiqueta}: ${barra.texto}',
        excludeSemantics: true,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              width: anchoEtiqueta,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  barra.etiqueta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            if (v != null)
              Positioned(
                key: ValueKey('barra-${barra.etiqueta}'),
                left: izquierda,
                width: math.max(largo, v == 0 ? 0 : 2),
                top: (alto - GraficoBarrasDivergentes._altoDeBarra) / 2,
                height: GraficoBarrasDivergentes._altoDeBarra,
                child: ColoredBox(color: barra.color),
              ),
            Positioned(
              left: textoEn,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  barra.texto,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: barra.color == ColoresGrafico.alerta
                        ? ColoresGrafico.alertaOscura
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PintorDelUmbral extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = ColoresGrafico.alertaOscura
      ..strokeWidth = 1.5;
    for (double y = 0; y < size.height; y += 7) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, math.min(y + 4, size.height)),
        pincel,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorDelUmbral anterior) => false;
}
