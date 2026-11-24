import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dominio_api.dart';
import '../../data/modelos/metricas.dart';

/// Se descartan al salir de la pantalla: las métricas cambian con cada
/// movimiento, y una copia vieja engaña más que una pantalla que vuelve a
/// cargar.
final metricasJefeProvider = FutureProvider.autoDispose
    .family<MetricasJefe, ({int obraId, PeriodoMetricas periodo})>(
      (ref, clave) =>
          ref.watch(metricasApiProvider).jefe(clave.obraId, clave.periodo),
    );

final metricasBodegaProvider = FutureProvider.autoDispose
    .family<MetricasBodega, ({int obraId, PeriodoMetricas periodo})>(
      (ref, clave) =>
          ref.watch(metricasApiProvider).bodega(clave.obraId, clave.periodo),
    );

final metricasEmpresaProvider = FutureProvider.autoDispose
    .family<MetricasEmpresa, PeriodoMetricas>(
      (ref, periodo) => ref.watch(metricasApiProvider).empresa(periodo),
    );
