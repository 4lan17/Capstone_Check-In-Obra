import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dominio_api.dart';
import '../../data/modelos/desviacion.dart';
import '../../data/modelos/presupuesto.dart';

/// El presupuesto de una obra, o `null` si todavía no tiene (D4).
final presupuestoDeObraProvider = FutureProvider.family<Presupuesto?, int>(
  (ref, obraId) => ref.watch(presupuestosApiProvider).porObra(obraId),
);

/// Los ítems de un presupuesto, con el precio que tenían al agregarse.
final itemsPresupuestoProvider =
    FutureProvider.family<List<PresupuestoItem>, int>(
      (ref, presupuestoId) =>
          ref.watch(presupuestosApiProvider).items(presupuestoId),
    );

/// La desviación de un presupuesto. Se descarta al salir de la pantalla: cada
/// vez que se abre se calcula de nuevo, porque cambia con cada despacho.
final desviacionProvider = FutureProvider.autoDispose.family<Desviacion, int>(
  (ref, presupuestoId) =>
      ref.watch(presupuestosApiProvider).desviacion(presupuestoId),
);
