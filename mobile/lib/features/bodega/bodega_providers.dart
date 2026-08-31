import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dominio_api.dart';
import '../../data/modelos/alerta.dart';
import '../../data/modelos/herramienta.dart';
import '../../data/modelos/kardex.dart';
import '../../data/modelos/material.dart';
import '../../data/modelos/obra.dart';
import '../../data/modelos/trabajador.dart';
import '../obra/obra_activa.dart';

/// Id de la obra en curso. Todo lo de abajo depende de él, así que si cambia
/// la obra, se recarga la bodega entera sola.
final _obraIdProvider = Provider<int?>(
  (ref) => ref.watch(obraActivaProvider).valueOrNull?.id,
);

/// Todos los movimientos de kardex de la obra.
///
/// Se traen de una vez, y no el stock material por material, porque el stock
/// **es** la suma con signo de estos movimientos: pedirlo aparte serían 34
/// peticiones para reconstruir lo que ya viene en una. Con una obra de meses
/// esta lista crece y habrá que paginarla o pedirle el agregado al servidor;
/// para un turno de bodega son unos cientos de filas.
final movimientosProvider = FutureProvider<List<MovimientoKardex>>((ref) async {
  final obraId = ref.watch(_obraIdProvider);
  if (obraId == null) return const [];
  final movimientos = await ref.watch(kardexApiProvider).porObra(obraId);
  return movimientos..sort((a, b) => b.fecha.compareTo(a.fecha));
});

/// Saldo por material, calculado igual que en el backend.
final stockPorMaterialProvider = Provider<AsyncValue<Map<int, double>>>((ref) {
  return ref.watch(movimientosProvider).whenData((movimientos) {
    final saldos = <int, double>{};
    for (final m in movimientos) {
      saldos[m.materialId] = (saldos[m.materialId] ?? 0) + m.cantidadConSigno;
    }
    return saldos;
  });
});

final catalogoProvider = FutureProvider<List<MaterialObra>>(
  (ref) => ref.watch(materialesApiProvider).listar(),
);

/// El catálogo cruzado con el saldo de la obra, ordenado por criticidad:
/// arriba lo que hay que reponer.
final bodegaProvider = Provider<AsyncValue<List<MaterialConStock>>>((ref) {
  final catalogo = ref.watch(catalogoProvider);
  final saldos = ref.watch(stockPorMaterialProvider);

  if (catalogo is AsyncError) {
    return AsyncValue.error(catalogo.error!, catalogo.stackTrace!);
  }
  if (saldos is AsyncError) {
    return AsyncValue.error(saldos.error!, saldos.stackTrace!);
  }
  if (!catalogo.hasValue || !saldos.hasValue) return const AsyncValue.loading();

  final lista =
      [
        for (final m in catalogo.requireValue)
          MaterialConStock(material: m, stock: saldos.requireValue[m.id] ?? 0),
      ]..sort((a, b) {
        final porCriticidad = a.criticidad.compareTo(b.criticidad);
        return porCriticidad != 0
            ? porCriticidad
            : a.material.nombre.compareTo(b.material.nombre);
      });

  return AsyncValue.data(lista);
});

/// Los trabajadores de la obra, para elegir a quién se le entrega o se le
/// presta. El backend los alcanza por la cuadrilla, así que un trabajador sin
/// cuadrilla no aparece — y eso hay que decirlo en pantalla, no dejar la lista
/// vacía sin explicación.
final trabajadoresDeObraProvider = FutureProvider<List<Trabajador>>((
  ref,
) async {
  final obraId = ref.watch(_obraIdProvider);
  if (obraId == null) return const [];
  final lista = await ref.watch(trabajadoresApiProvider).porObra(obraId);
  return lista..sort((a, b) => a.nombre.compareTo(b.nombre));
});

final herramientasProvider = FutureProvider<List<Herramienta>>(
  (ref) => ref.watch(herramientasApiProvider).listar(),
);

final prestamosProvider = FutureProvider<List<Prestamo>>((ref) async {
  final obraId = ref.watch(_obraIdProvider);
  if (obraId == null) return const [];
  return ref.watch(prestamosApiProvider).porObra(obraId);
});

/// Los préstamos que siguen abiertos: la herramienta está fuera de bodega.
final prestamosAbiertosProvider = Provider<AsyncValue<List<Prestamo>>>(
  (ref) => ref
      .watch(prestamosProvider)
      .whenData((lista) => lista.where((p) => p.abierto).toList()),
);

final alertasProvider = FutureProvider<List<Alerta>>((ref) async {
  final obraId = ref.watch(_obraIdProvider);
  if (obraId == null) return const [];

  // El backend no tiene tareas programadas: las alertas se detectan cuando
  // alguien mira. Barrer acá es lo que hace que la lista esté al día al
  // abrirla, en vez de mostrar lo que quedó de ayer.
  final api = ref.watch(alertasApiProvider);
  await api.detectarNoDevueltas(obraId);
  await api.detectarStockCritico(obraId);

  final alertas = await api.porObra(obraId);
  return alertas..sort((a, b) => b.fecha.compareTo(a.fecha));
});

final alertasSinResolverProvider = Provider<AsyncValue<List<Alerta>>>(
  (ref) => ref
      .watch(alertasProvider)
      .whenData((lista) => lista.where((a) => !a.resuelto).toList()),
);

/// Los movimientos de hoy — el turno en curso, para los contadores del inicio
/// y el resumen del cierre.
final movimientosDeHoyProvider = Provider<AsyncValue<List<MovimientoKardex>>>((
  ref,
) {
  return ref.watch(movimientosProvider).whenData((lista) {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    return lista.where((m) => m.fecha.isAfter(hoy)).toList();
  });
});

/// Cuánta plata hay parada en la obra.
///
/// Son dos cifras distintas y las dos importan: el material que está en bodega
/// es capital inmovilizado, y las herramientas que están afuera son el valor
/// que hay que recuperar antes de cerrar el turno. Sumarlas en un solo número
/// las volvería inútiles.
class ValorEnObra {
  const ValorEnObra({
    required this.materialesEnBodega,
    required this.herramientasFuera,
    required this.herramientasPrestadas,
  });

  /// Suma de stock × precio unitario de cada material.
  final double materialesEnBodega;

  /// Valor de reposición de las herramientas que siguen prestadas.
  final double herramientasFuera;

  final int herramientasPrestadas;

  double get total => materialesEnBodega + herramientasFuera;
}

final valorEnObraProvider = Provider<AsyncValue<ValorEnObra>>((ref) {
  final bodega = ref.watch(bodegaProvider);
  final abiertos = ref.watch(prestamosAbiertosProvider);
  final herramientas = ref.watch(herramientasProvider);

  if (!bodega.hasValue || !abiertos.hasValue || !herramientas.hasValue) {
    return const AsyncValue.loading();
  }

  final materiales = bodega.requireValue.fold<double>(
    0,
    // El saldo puede ser negativo si hubo un descuadre; se cuenta tal cual en
    // vez de topar en cero, porque maquillarlo escondería el problema.
    (total, m) => total + m.stock * m.material.precioUnitario,
  );

  final porId = {for (final h in herramientas.requireValue) h.id: h};
  final fuera = abiertos.requireValue.fold<double>(
    0,
    (total, p) => total + (porId[p.herramientaId]?.valorReposicion ?? 0),
  );

  return AsyncValue.data(
    ValorEnObra(
      materialesEnBodega: materiales,
      herramientasFuera: fuera,
      herramientasPrestadas: abiertos.requireValue.length,
    ),
  );
});

/// Recarga todo lo que depende de la obra. Se llama tras registrar un
/// movimiento o una devolución, porque cambian varias pantallas a la vez:
/// el saldo del material, los contadores del turno y las alertas.
void recargarBodega(WidgetRef ref) {
  ref.invalidate(movimientosProvider);
  ref.invalidate(prestamosProvider);
  ref.invalidate(alertasProvider);
  ref.invalidate(herramientasProvider);
}

/// La obra en curso, para los encabezados.
final obraEnCursoProvider = Provider<Obra?>(
  (ref) => ref.watch(obraActivaProvider).valueOrNull,
);
