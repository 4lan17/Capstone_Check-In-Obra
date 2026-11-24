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
import '../admin/shell_admin.dart' show empresaProvider;
import 'metricas_providers.dart';
import 'pantalla_metricas.dart';

/// Cómo va la empresa entera: alertas, desviación de cada obra y quiénes la
/// usan. Es del administrador.
class PantallaMetricasAdmin extends ConsumerWidget {
  const PantallaMetricasAdmin({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empresa = ref.watch(empresaProvider).value;
    return PantallaMetricas<MetricasEmpresa>(
      subtitulo: empresa?.nombre ?? '',
      observar: (ref, periodo) => ref.watch(metricasEmpresaProvider(periodo)),
      invalidar: (ref, periodo) =>
          ref.invalidate(metricasEmpresaProvider(periodo)),
      tarjetas: (context, ref, m, periodo) => [
        _Alertas(m: m),
        _DesviacionPorObra(m: m),
        _UsuariosPorRol(m: m),
      ],
    );
  }
}

class _Alertas extends StatelessWidget {
  const _Alertas({required this.m});

  final MetricasEmpresa m;

  @override
  Widget build(BuildContext context) {
    const titulo = 'Alertas por semana';
    if (m.alertasPorSemana.isEmpty || m.sinAlertas) {
      return const TarjetaMetrica(
        titulo: titulo,
        child: GraficoVacio(
          mensaje: 'No hubo alertas en este periodo.',
          alto: 128,
        ),
      );
    }

    final ultima = m.alertasPorSemana.last;
    return TarjetaMetrica(
      titulo: titulo,
      cifra: '${ultima.generadas}',
      detalle:
          'generadas en ${ultima.etiqueta} · ${ultima.resueltas} resueltas hasta hoy',
      leyenda: const [
        ItemLeyenda(
          etiqueta: 'Generadas',
          color: ColoresGrafico.ejecutado,
          estilo: EstiloLeyenda.linea,
        ),
        // Las resueltas son de las generadas esa semana, contadas hoy.
        ItemLeyenda(
          etiqueta: 'Resueltas hasta hoy',
          color: ColoresGrafico.referencia,
          estilo: EstiloLeyenda.lineaPunteada,
        ),
      ],
      child: GraficoLinea(
        etiquetasX: [for (final s in m.alertasPorSemana) s.etiqueta],
        descripcion:
            '${ultima.generadas} alertas generadas en ${ultima.etiqueta}, de las '
            'que ${ultima.resueltas} están resueltas hasta hoy',
        series: [
          SerieLinea(
            nombre: 'Generadas',
            valores: [
              for (final s in m.alertasPorSemana) s.generadas.toDouble(),
            ],
            color: ColoresGrafico.ejecutado,
          ),
          SerieLinea(
            nombre: 'Resueltas hasta hoy',
            valores: [
              for (final s in m.alertasPorSemana) s.resueltas.toDouble(),
            ],
            color: ColoresGrafico.referencia,
            punteada: true,
          ),
        ],
      ),
    );
  }
}

class _DesviacionPorObra extends StatelessWidget {
  const _DesviacionPorObra({required this.m});

  final MetricasEmpresa m;

  @override
  Widget build(BuildContext context) {
    const titulo = 'Desviación por obra';
    if (m.desviacionPorObra.isEmpty) {
      return const TarjetaMetrica(
        titulo: titulo,
        child: GraficoVacio(
          mensaje: 'Todavía no hay obras para comparar.',
          alto: 128,
        ),
      );
    }

    final umbral = m.umbralPct;
    final peor = m.masDesviada;
    final String? cifra = peor == null
        ? null
        : Formato.porcentajeConSigno(peor.desviacionPct!);
    final detalle = peor == null
        ? 'Ninguna obra tiene presupuesto contra el cual medirse'
        : peor.superaUmbral(umbral)
        ? '${peor.nombre} supera el umbral de la empresa'
        : '${peor.nombre} es la obra con más desviación';

    Color color(DesviacionDeObra o) {
      final v = o.desviacionPct;
      if (v == null) return ColoresGrafico.referencia;
      if (o.superaUmbral(umbral)) return ColoresGrafico.alerta;
      return v > 0 ? ColoresGrafico.ejecutado : ColoresGrafico.neutroMedio;
    }

    return TarjetaMetrica(
      titulo: titulo,
      cifra: cifra,
      colorCifra: (peor?.superaUmbral(umbral) ?? false)
          ? ColoresGrafico.alertaOscura
          : ColoresGrafico.neutro,
      detalle: detalle,
      child: GraficoBarrasDivergentes(
        umbral: umbral,
        etiquetaUmbral: umbral == null
            ? null
            : 'umbral ${Formato.porcentaje(umbral)}',
        descripcion: 'Desviación del gasto contra el presupuesto de cada obra',
        barras: [
          for (final o in m.desviacionPorObra)
            BarraDivergente(
              etiqueta: o.nombre,
              valor: o.desviacionPct,
              color: color(o),
              texto: o.desviacionPct == null
                  ? 'sin presupuesto'
                  : Formato.porcentajeConSigno(o.desviacionPct!)
                        .replaceAll('−', '-'),
              descripcion: o.desviacionPct == null
                  ? '${o.nombre}: sin presupuesto'
                  : '${o.nombre}: ${Formato.porcentajeConSigno(o.desviacionPct!)}'
                        '${o.superaUmbral(umbral) ? ', supera el umbral' : ''}',
            ),
        ],
      ),
    );
  }
}

class _UsuariosPorRol extends StatelessWidget {
  const _UsuariosPorRol({required this.m});

  final MetricasEmpresa m;

  static const _orden = ['TRABAJADOR', 'BODEGUERO', 'JEFE_TERRENO', 'ADMIN'];

  static const _nombres = {
    'TRABAJADOR': 'Trabajadores',
    'BODEGUERO': 'Bodegueros',
    'JEFE_TERRENO': 'Jefes de terreno',
    'ADMIN': 'Administradores',
  };

  /// Cómo se dice «son …» del rol más numeroso.
  static const _sonDe = {
    'TRABAJADOR': 'trabajadores de obra',
    'BODEGUERO': 'bodegueros',
    'JEFE_TERRENO': 'jefes de terreno',
    'ADMIN': 'administradores',
  };

  static const _colores = [
    ColoresGrafico.ejecutado,
    ColoresGrafico.neutro,
    ColoresGrafico.referencia,
    ColoresGrafico.presupuesto,
  ];

  static String _nombreDe(String rol) =>
      _nombres[rol] ??
      '${rol[0]}${rol.substring(1).toLowerCase().replaceAll('_', ' ')}';

  @override
  Widget build(BuildContext context) {
    const titulo = 'Usuarios por rol';
    final total = m.totalUsuarios;
    if (total == 0) {
      return const TarjetaMetrica(
        titulo: titulo,
        child: GraficoVacio(
          mensaje: 'Todavía no hay usuarios en la empresa.',
          alto: 112,
        ),
      );
    }

    final roles = [
      ..._orden.where(m.usuariosPorRol.containsKey),
      ...m.usuariosPorRol.keys.where((r) => !_orden.contains(r)),
    ];
    final mayor = roles.reduce(
      (a, b) =>
          (m.usuariosPorRol[a] ?? 0) >= (m.usuariosPorRol[b] ?? 0) ? a : b,
    );
    final segmentos = [
      for (var i = 0; i < roles.length; i++)
        SegmentoDona(
          etiqueta: _nombreDe(roles[i]),
          valor: (m.usuariosPorRol[roles[i]] ?? 0).toDouble(),
          color: i < _colores.length ? _colores[i] : ColoresGrafico.gris,
          texto:
              '${((m.usuariosPorRol[roles[i]] ?? 0) / total * 100).round()} %',
        ),
    ];
    return TarjetaMetrica(
      titulo: titulo,
      cifra: '${m.usuariosPorRol[mayor]}',
      detalle: 'son ${_sonDe[mayor] ?? _nombreDe(mayor).toLowerCase()}',
      child: GraficoDona(
        segmentos: segmentos,
        centroValor: '$total',
        centroEtiqueta: 'usuarios',
        descripcion: [for (final s in segmentos) '${s.etiqueta} ${s.texto}']
            .join(', '),
      ),
    );
  }
}
