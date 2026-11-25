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
import 'metricas_providers.dart';
import 'pantalla_metricas.dart';

/// Cómo va la obra en plata: lo ejecutado contra lo presupuestado, por
/// material y en total. Es del jefe de terreno.
const _otros = etiquetaOtrosMateriales;

class PantallaMetricasJefe extends ConsumerWidget {
  const PantallaMetricasJefe({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obra = ref.watch(obraEnCursoProvider);
    if (obra == null) return const SizedBox.shrink();
    return PantallaMetricas<MetricasJefe>(
      subtitulo: obra.nombre,
      observar: (ref, periodo) =>
          ref.watch(metricasJefeProvider((obraId: obra.id, periodo: periodo))),
      invalidar: (ref, periodo) => ref.invalidate(
        metricasJefeProvider((obraId: obra.id, periodo: periodo)),
      ),
      tarjetas: (context, ref, m, periodo) => [
        _GastoAcumulado(m: m),
        _PresupuestadoVsEjecutado(m: m),
        _EjecutadoPorMaterial(m: m),
      ],
    );
  }
}

class _GastoAcumulado extends StatelessWidget {
  const _GastoAcumulado({required this.m});

  final MetricasJefe m;

  @override
  Widget build(BuildContext context) {
    final g = m.gastoAcumulado;
    final conPresupuesto = g.presupuestoTotal > 0;
    const titulo = 'Gasto acumulado por semana';

    if (g.serie.isEmpty) {
      return const TarjetaMetrica(
        titulo: titulo,
        child: GraficoVacio(
          mensaje: 'Todavía no hay gasto registrado en este periodo.',
          alto: 128,
        ),
      );
    }

    final n = g.serie.length;
    return TarjetaMetrica(
      titulo: titulo,
      cifra: Formato.millones(g.ejecutadoTotal),
      colorCifra: g.superaPresupuesto
          ? ColoresGrafico.alertaOscura
          : ColoresGrafico.neutro,
      detalle: conPresupuesto
          ? 'ejecutado · presupuesto ${Formato.millones(g.presupuestoTotal)}'
          : 'ejecutado · sin presupuesto',
      leyenda: [
        const ItemLeyenda(
          etiqueta: 'Ejecutado acumulado',
          color: ColoresGrafico.ejecutado,
          estilo: EstiloLeyenda.linea,
        ),
        if (conPresupuesto)
          const ItemLeyenda(
            etiqueta: 'Presupuesto',
            color: ColoresGrafico.referencia,
            estilo: EstiloLeyenda.lineaPunteada,
          ),
      ],
      child: GraficoLinea(
        etiquetasX: [for (final p in g.serie) p.etiqueta],
        formatoY: Formato.soloMillones,
        marcaFinal: g.superaPresupuesto ? 'Supera el presupuesto' : null,
        descripcion:
            'Gasto acumulado: de ${Formato.millones(g.serie.first.ejecutadoAcumulado)} '
            'a ${Formato.millones(g.ejecutadoTotal)} ejecutados'
            '${conPresupuesto ? ', contra un presupuesto de ${Formato.millones(g.presupuestoTotal)}' : ', sin presupuesto'}'
            '${g.superaPresupuesto ? '. Supera el presupuesto' : ''}',
        series: [
          SerieLinea(
            nombre: 'Ejecutado acumulado',
            valores: [for (final p in g.serie) p.ejecutadoAcumulado],
            color: ColoresGrafico.ejecutado,
            conArea: true,
          ),
          if (conPresupuesto)
            SerieLinea(
              nombre: 'Presupuesto',
              valores: List.filled(n, g.presupuestoTotal),
              color: ColoresGrafico.referencia,
              punteada: true,
            ),
        ],
      ),
    );
  }
}

class _PresupuestadoVsEjecutado extends StatelessWidget {
  const _PresupuestadoVsEjecutado({required this.m});

  final MetricasJefe m;

  @override
  Widget build(BuildContext context) {
    const titulo = 'Presupuestado vs ejecutado';
    if (m.porMaterial.isEmpty) {
      return const TarjetaMetrica(
        titulo: titulo,
        child: GraficoVacio(
          mensaje: 'Todavía no hay materiales con gasto en este periodo.',
          alto: 128,
        ),
      );
    }

    final peor = m.masPasado;
    final pct = peor?.desviacionPct;
    final String? cifra;
    final String detalle;
    if (peor == null || pct == null) {
      cifra = null;
      detalle = 'Los materiales consumidos no tienen presupuesto';
    } else if (pct <= 0) {
      cifra = null;
      detalle = 'Ningún material se pasó del presupuesto';
    } else {
      cifra = Formato.porcentajeConSigno(pct);
      detalle = '${peor.nombre}, el material que más se pasó';
    }

    return TarjetaMetrica(
      titulo: titulo,
      cifra: cifra,
      colorCifra: (peor?.superaUmbral ?? false)
          ? ColoresGrafico.alertaOscura
          : ColoresGrafico.neutro,
      detalle: detalle,
      leyenda: const [
        ItemLeyenda(
          etiqueta: 'Presupuestado',
          color: ColoresGrafico.presupuesto,
        ),
        ItemLeyenda(etiqueta: 'Ejecutado', color: ColoresGrafico.ejecutado),
        ItemLeyenda(etiqueta: 'Sobre umbral', color: ColoresGrafico.alerta),
      ],
      child: GraficoBarrasAgrupadas(
        descripcion:
            'Presupuestado contra ejecutado de los materiales de mayor gasto',
        grupos: [
          for (final x in m.porMaterial)
            GrupoDeBarras(
              etiqueta: x.nombre,
              descripcion:
                  '${x.nombre}: presupuestado ${Formato.millones(x.presupuestado)}, '
                  'ejecutado ${Formato.millones(x.ejecutado)}'
                  '${x.desviacionPct == null ? ', sin presupuesto' : ', ${Formato.porcentajeConSigno(x.desviacionPct!)}'}'
                  '${x.superaUmbral ? ', supera el umbral' : ''}',
              barras: [
                BarraDeGrupo(
                  valor: x.presupuestado,
                  color: ColoresGrafico.presupuesto,
                  texto: x.presupuestado > 0
                      ? Formato.millones(x.presupuestado)
                      : 'sin presupuesto',
                ),
                BarraDeGrupo(
                  valor: x.ejecutado,
                  color: x.superaUmbral
                      ? ColoresGrafico.alerta
                      : ColoresGrafico.ejecutado,
                  texto: Formato.millones(x.ejecutado),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EjecutadoPorMaterial extends StatelessWidget {
  const _EjecutadoPorMaterial({required this.m});

  final MetricasJefe m;

  @override
  Widget build(BuildContext context) {
    const titulo = 'Ejecutado por material';
    final partes = m.partesDeDona;
    if (partes.isEmpty) {
      return const TarjetaMetrica(
        titulo: titulo,
        child: GraficoVacio(
          mensaje: 'Todavía no hay gasto por material en este periodo.',
          alto: 128,
        ),
      );
    }

    // La cifra habla del material más pesado **con nombre**: «Otros» suele ser
    // más grande, pero no es un material.
    final nombrados = partes.where((p) => p.etiqueta != _otros).toList();
    final mayor = nombrados.isEmpty
        ? null
        : nombrados.reduce((a, b) => a.valor >= b.valor ? a : b);
    final segmentos = [
      for (var i = 0; i < partes.length; i++)
        SegmentoDona(
          etiqueta: partes[i].etiqueta,
          valor: partes[i].valor,
          // «Otros materiales» siempre en el gris claro: no es un material.
          color: partes[i].etiqueta == _otros
              ? ColoresGrafico.otros
              : ColoresGrafico.categoricos[i %
                    ColoresGrafico.categoricos.length],
          texto: '${(partes[i].proporcion * 100).round()} %',
        ),
    ];
    return TarjetaMetrica(
      titulo: titulo,
      cifra: mayor == null ? null : '${(mayor.proporcion * 100).round()} %',
      detalle: mayor == null ? null : 'del gasto es ${mayor.etiqueta}',
      child: GraficoDona(
        segmentos: segmentos,
        centroValor: Formato.millones(m.totalPartes),
        centroEtiqueta: 'ejecutado',
        descripcion: [for (final s in segmentos) '${s.etiqueta} ${s.texto}']
            .join(', '),
      ),
    );
  }
}
