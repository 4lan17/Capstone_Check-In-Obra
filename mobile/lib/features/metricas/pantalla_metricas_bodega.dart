import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../data/modelos/metricas.dart';
import '../../shared_widgets/graficos/colores_grafico.dart';
import '../../shared_widgets/graficos/grafico_barras.dart';
import '../../shared_widgets/graficos/grafico_dona.dart';
import '../../shared_widgets/graficos/grafico_linea.dart';
import '../../shared_widgets/graficos/grafico_vacio.dart';
import '../../shared_widgets/graficos/tarjeta_metrica.dart';
import '../bodega/bodega_providers.dart';
import '../bodega/pantalla_bodega.dart' show unidadDe;
import 'etiquetas_de_fechas.dart';
import 'metricas_providers.dart';
import 'pantalla_metricas.dart';

/// Cómo se mueve la bodega: entradas y salidas en el tiempo, lo que más sale
/// y cómo están las herramientas.
class PantallaMetricasBodega extends ConsumerWidget {
  const PantallaMetricasBodega({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obra = ref.watch(obraEnCursoProvider);
    if (obra == null) return const SizedBox.shrink();
    return PantallaMetricas<MetricasBodega>(
      subtitulo: obra.nombre,
      observar: (ref, periodo) => ref.watch(
        metricasBodegaProvider((obraId: obra.id, periodo: periodo)),
      ),
      invalidar: (ref, periodo) => ref.invalidate(
        metricasBodegaProvider((obraId: obra.id, periodo: periodo)),
      ),
      tarjetas: (context, ref, m, periodo) => [
        _Movimientos(m: m, periodo: periodo),
        _MasDespachados(m: m),
        _Herramientas(m: m),
      ],
    );
  }
}

/// «en la semana», «en el mes», «en toda la obra».
String _enElPeriodo(PeriodoMetricas p) => switch (p) {
  PeriodoMetricas.sieteDias => 'en la semana',
  PeriodoMetricas.treintaDias => 'en el mes',
  PeriodoMetricas.todaLaObra => 'en toda la obra',
};

class _Movimientos extends StatelessWidget {
  const _Movimientos({required this.m, required this.periodo});

  final MetricasBodega m;
  final PeriodoMetricas periodo;

  @override
  Widget build(BuildContext context) {
    final por = switch (m.granularidad.toUpperCase()) {
      'SEMANA' => 'semana',
      'MES' => 'mes',
      _ => 'día',
    };
    final titulo = 'Movimientos por $por';
    if (m.sinMovimientos) {
      return TarjetaMetrica(
        titulo: titulo,
        child: const GraficoVacio(
          mensaje: 'Todavía no hay movimientos en este periodo.',
          alto: 128,
        ),
      );
    }

    return TarjetaMetrica(
      titulo: titulo,
      cifra: '${m.totalSalidas}',
      detalle: 'salidas ${_enElPeriodo(periodo)} · ${m.totalEntradas} entradas',
      leyenda: const [
        ItemLeyenda(
          etiqueta: 'Salidas (despacho y consumo)',
          color: ColoresGrafico.ejecutado,
          estilo: EstiloLeyenda.linea,
        ),
        ItemLeyenda(
          etiqueta: 'Entradas (recepción)',
          color: ColoresGrafico.referencia,
          estilo: EstiloLeyenda.lineaPunteada,
        ),
      ],
      child: GraficoLinea(
        etiquetasX: etiquetasDeFechas([
          for (final x in m.movimientos) x.fecha,
        ], m.granularidad),
        descripcion:
            '${m.totalSalidas} salidas y ${m.totalEntradas} entradas '
            '${_enElPeriodo(periodo)}, por $por',
        series: [
          SerieLinea(
            nombre: 'Salidas',
            valores: [for (final x in m.movimientos) x.salidas.toDouble()],
            color: ColoresGrafico.ejecutado,
          ),
          SerieLinea(
            nombre: 'Entradas',
            valores: [for (final x in m.movimientos) x.entradas.toDouble()],
            color: ColoresGrafico.referencia,
            punteada: true,
          ),
        ],
      ),
    );
  }
}

class _MasDespachados extends ConsumerWidget {
  const _MasDespachados({required this.m});

  final MetricasBodega m;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const titulo = 'Materiales más despachados';
    if (m.masDespachados.isEmpty) {
      return const TarjetaMetrica(
        titulo: titulo,
        child: GraficoVacio(
          mensaje: 'Todavía no se despachó material en este periodo.',
          alto: 112,
        ),
      );
    }

    // La unidad sale del catálogo, si ya cargó; si no, la cantidad va sola.
    final catalogo = ref.watch(catalogoProvider).value ?? const [];
    final categorias = {for (final c in catalogo) c.id: c.categoria};
    String cantidad(MaterialDespachado d) {
      final unidad = categorias[d.materialId];
      final n = Formato.cantidad(d.cantidad);
      return unidad == null ? n : '$n ${unidadDe(unidad)}';
    }

    final primero = m.masDespachados.first;
    return TarjetaMetrica(
      titulo: titulo,
      cifra: cantidad(primero),
      detalle: 'de ${primero.nombre}',
      child: GraficoBarrasAgrupadas(
        descripcion: 'Los materiales que más salieron de bodega',
        grupos: [
          for (var i = 0; i < m.masDespachados.length; i++)
            GrupoDeBarras(
              etiqueta: m.masDespachados[i].nombre,
              descripcion:
                  '${m.masDespachados[i].nombre}: ${cantidad(m.masDespachados[i])}',
              barras: [
                BarraDeGrupo(
                  valor: m.masDespachados[i].cantidad,
                  // El primero, el que más salió, va en naranja.
                  color: i == 0
                      ? ColoresGrafico.ejecutado
                      : ColoresGrafico.neutroMedio,
                  texto: cantidad(m.masDespachados[i]),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Herramientas extends StatelessWidget {
  const _Herramientas({required this.m});

  final MetricasBodega m;

  static const _orden = ['DISPONIBLE', 'PRESTADA', 'MANTENCION', 'NO_DEVUELTA'];

  static const _nombres = {
    'DISPONIBLE': 'Disponibles',
    'PRESTADA': 'Prestadas',
    'MANTENCION': 'En mantención',
    'NO_DEVUELTA': 'No devueltas',
  };

  static const _colores = {
    'DISPONIBLE': ColoresGrafico.neutro,
    'PRESTADA': ColoresGrafico.ejecutado,
    'MANTENCION': ColoresGrafico.presupuesto,
    'NO_DEVUELTA': ColoresGrafico.alertaOscura,
  };

  static String _nombreDe(String estado) =>
      _nombres[estado] ??
      '${estado[0]}${estado.substring(1).toLowerCase().replaceAll('_', ' ')}';

  @override
  Widget build(BuildContext context) {
    // Las herramientas son de la empresa: no hay "herramientas de esta obra".
    const titulo = 'Herramientas de la empresa';
    if (m.totalHerramientas == 0) {
      return const TarjetaMetrica(
        titulo: titulo,
        child: GraficoVacio(
          mensaje: 'La empresa todavía no tiene herramientas registradas.',
          alto: 112,
        ),
      );
    }

    final estados = [
      ..._orden.where(m.herramientasPorEstado.containsKey),
      ...m.herramientasPorEstado.keys.where((e) => !_orden.contains(e)),
    ];
    final prestadas = m.herramientasPorEstado['PRESTADA'] ?? 0;
    final segmentos = [
      for (final e in estados)
        SegmentoDona(
          etiqueta: _nombreDe(e),
          valor: (m.herramientasPorEstado[e] ?? 0).toDouble(),
          color: _colores[e] ?? ColoresGrafico.gris,
          texto: '${m.herramientasPorEstado[e] ?? 0}',
        ),
    ];
    return TarjetaMetrica(
      titulo: titulo,
      cifra: '${m.prestadasEnEstaObra}',
      detalle: 'prestadas en esta obra · $prestadas en toda la empresa',
      child: GraficoDona(
        segmentos: segmentos,
        centroValor: '${m.totalHerramientas}',
        centroEtiqueta: 'en total',
        descripcion: [for (final s in segmentos) '${s.etiqueta} ${s.texto}']
            .join(', '),
      ),
    );
  }
}
