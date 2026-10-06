import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/api_client.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/herramienta.dart';
import '../../data/modelos/material.dart';
import '../../data/modelos/pedido_especial.dart';
import '../../data/modelos/perfil_trabajador.dart';
import '../../data/modelos/solicitud.dart';
import '../auth/sesion_controller.dart';
import '../bodega/pantalla_bodega.dart';

/// El trabajador que entró. Todo lo demás de su app cuelga de acá: sin saber
/// su obra no hay a qué bodega pedirle nada.
///
/// Sin señal se muestra la última copia guardada, para que la credencial
/// sirva igual en el mesón. Solo ante un fallo de red: si el servidor
/// respondió —un 404 de ficha sin crear, un 401—, esa respuesta manda.
final perfilTrabajadorProvider = FutureProvider<PerfilTrabajador>((ref) async {
  final storage = ref.watch(sesionStorageProvider);
  try {
    final perfil = await ref.watch(trabajadoresApiProvider).yo();
    await storage.guardarPerfilTrabajador(perfil);
    return perfil;
  } on DioException {
    final usuarioId = ref.read(sesionProvider).valueOrNull?.usuarioId;
    final guardado = usuarioId == null
        ? null
        : await storage.leerPerfilTrabajador(usuarioId);
    if (guardado == null) rethrow;
    return guardado;
  }
});

/// Sus préstamos, abiertos y cerrados, del más reciente al más antiguo.
final misPrestamosProvider = FutureProvider<List<Prestamo>>((ref) async {
  final lista = await ref.watch(prestamosApiProvider).mios();
  final cero = DateTime.fromMillisecondsSinceEpoch(0);
  return lista..sort(
    (a, b) => (b.fechaPrestamo ?? cero).compareTo(a.fechaPrestamo ?? cero),
  );
});

/// Lo que tiene en su poder ahora: vencidos arriba, y después por la fecha en
/// que tiene que devolver.
final enMiPoderProvider = Provider<AsyncValue<List<Prestamo>>>(
  (ref) => ref.watch(misPrestamosProvider).whenData((lista) {
    final lejos = DateTime(9999);
    return lista.where((p) => p.abierto).toList()..sort((a, b) {
      if (a.vencido != b.vencido) return a.vencido ? -1 : 1;
      return (a.fechaDevolEsperada ?? lejos).compareTo(
        b.fechaDevolEsperada ?? lejos,
      );
    });
  }),
);

/// De dónde viene una solicitud propia. Cada origen es un endpoint distinto
/// para cancelar y para confirmar.
enum OrigenSolicitud { material, herramienta, especial }

/// Algo que pidió, venga del catálogo o sea un pedido especial.
///
/// Para quien pide son la misma cosa —"pedí algo, ¿en qué va?"— así que se
/// muestran en una sola lista. Por debajo son tres endpoints.
class MiSolicitud {
  const MiSolicitud({
    required this.id,
    required this.itemId,
    required this.origen,
    required this.nombre,
    required this.cantidad,
    required this.estado,
    required this.fecha,
    required this.motivoRechazo,
    required this.resueltoPorNombre,
    this.descripcion,
    this.notaBodega,
    this.entregado,
    this.entregaParcial = false,
    this.esHerramientaEspecial = false,
  });

  factory MiSolicitud.deMaterial(
    SolicitudMaterial s, {
    required String unidad,
  }) => MiSolicitud(
    id: s.id,
    itemId: s.materialId,
    origen: OrigenSolicitud.material,
    nombre: s.materialNombre,
    cantidad: '${Formato.cantidad(s.cantidad)} $unidad',
    estado: s.estado,
    fecha: s.fechaSolicitud,
    motivoRechazo: s.motivoRechazo,
    resueltoPorNombre: s.resueltoPorNombre,
    descripcion: s.descripcion,
    entregado: s.cantidadEntregada == null
        ? null
        : '${Formato.cantidad(s.cantidadEntregada!)} $unidad',
    entregaParcial: s.entregaParcial,
  );

  factory MiSolicitud.deHerramienta(SolicitudHerramienta s) => MiSolicitud(
    id: s.id,
    itemId: s.herramientaId,
    origen: OrigenSolicitud.herramienta,
    nombre: s.herramientaNombre,
    cantidad: s.cantidad == 1 ? '1 unidad' : '${s.cantidad} unidades',
    estado: s.estado,
    fecha: s.fechaSolicitud,
    motivoRechazo: s.motivoRechazo,
    resueltoPorNombre: s.resueltoPorNombre,
    descripcion: s.descripcion,
    // Una herramienta se presta entera: si la aprobaron, le entregaron lo
    // que pidió.
    entregado: const {'APROBADA', 'ENTREGADA'}.contains(s.estado)
        ? (s.cantidad == 1 ? '1 unidad' : '${s.cantidad} unidades')
        : null,
  );

  factory MiSolicitud.dePedido(PedidoEspecial p) => MiSolicitud(
    id: p.id,
    itemId: p.materialId ?? p.herramientaId,
    origen: OrigenSolicitud.especial,
    nombre: p.nombre,
    cantidad: p.esHerramienta && p.unidad == null
        ? (p.cantidad == 1 ? '1 unidad' : '${p.cantidadConUnidad} unidades')
        : p.cantidadConUnidad,
    estado: p.estado,
    fecha: p.fechaSolicitud,
    motivoRechazo: p.motivoRechazo,
    resueltoPorNombre: p.gestionadoPorNombre,
    descripcion: p.descripcion,
    notaBodega: p.notaBodega,
    esHerramientaEspecial: p.esHerramienta,
  );

  final int id;

  /// El material o la herramienta del catálogo, si lo es. Nulo en un pedido
  /// especial de algo que no está en el catálogo.
  final int? itemId;
  final OrigenSolicitud origen;
  final String nombre;
  final String cantidad;

  /// `EstadoSolicitud` o `EstadoPedidoEspecial`, según el origen.
  final String estado;
  final DateTime? fecha;
  final String? motivoRechazo;
  final String? resueltoPorNombre;

  /// Para qué lo pidió.
  final String? descripcion;

  /// Lo que bodega le avisó mientras lo conseguía.
  final String? notaBodega;

  /// Lo que bodega le entregó, con su unidad. Nulo mientras no se aprueba y
  /// en los pedidos especiales, que no registran cantidad entregada.
  final String? entregado;

  /// Le entregaron menos de lo que pidió.
  final bool entregaParcial;
  final bool esHerramientaEspecial;

  bool get esEspecial => origen == OrigenSolicitud.especial;

  bool get esHerramienta =>
      origen == OrigenSolicitud.herramienta || esHerramientaEspecial;

  /// Espera algo de bodega: sin atender, o un pedido especial en camino.
  bool get enEspera => esEspecial
      ? const {'PENDIENTE', 'EN_GESTION', 'LISTO_PARA_RETIRO'}.contains(estado)
      : estado == estadoPendiente;

  /// Para marcar en las listas de pedir lo que ya tiene pedido.
  bool get pendiente => enEspera;

  /// Todavía la puede retirar: nadie la atendió ni la consiguió.
  bool get cancelable => esEspecial
      ? estado == 'PENDIENTE' || estado == 'EN_GESTION'
      : estado == estadoPendiente;

  /// Bodega ya se la pasó y falta que él confirme que la recibió.
  bool get porConfirmar =>
      esEspecial ? estado == 'ENTREGADO' : estado == 'APROBADA';

  bool get rechazada => estado == 'RECHAZADA' || estado == 'RECHAZADO';

  bool get retirada => estado == 'CANCELADA' || estado == 'CANCELADO';
}

/// Todo lo que pidió —catálogo y pedidos especiales— y la más nueva primero.
///
/// Las consultas van en paralelo, pero un fallo en una no deja las otras en
/// blanco sin avisar: el error sube entero y la pantalla ofrece reintentar.
final misSolicitudesProvider = FutureProvider<List<MiSolicitud>>((ref) async {
  final api = ref.watch(solicitudesApiProvider);
  final (materiales, herramientas, especiales) = await (
    api.misMateriales(),
    api.misHerramientas(),
    ref.watch(pedidosEspecialesApiProvider).mios(),
  ).wait;

  // La unidad sale de la categoría del material, que la solicitud no trae.
  // Si el catálogo no carga, las solicitudes se muestran igual, sin unidad:
  // es un adorno, no una razón para dejar la lista en error.
  final catalogo = await ref
      .watch(catalogoTrabajadorProvider.future)
      .catchError((_) => const <MaterialObra>[]);
  final categoria = {for (final m in catalogo) m.id: m.categoria};

  final cero = DateTime.fromMillisecondsSinceEpoch(0);
  return [
    for (final s in materiales)
      MiSolicitud.deMaterial(
        s,
        unidad: unidadDe(categoria[s.materialId] ?? ''),
      ),
    for (final s in herramientas) MiSolicitud.deHerramienta(s),
    for (final p in especiales) MiSolicitud.dePedido(p),
  ]..sort((a, b) => (b.fecha ?? cero).compareTo(a.fecha ?? cero));
});

/// Las que esperan a bodega.
final misPendientesProvider = Provider<AsyncValue<List<MiSolicitud>>>(
  (ref) => ref
      .watch(misSolicitudesProvider)
      .whenData((l) => l.where((s) => s.enEspera).toList()),
);

/// Lo que bodega ya le pasó y falta confirmar. Va arriba de todo en Inicio:
/// hasta que lo confirme, para el sistema sigue "en el aire".
final porConfirmarProvider = Provider<AsyncValue<List<MiSolicitud>>>(
  (ref) => ref
      .watch(misSolicitudesProvider)
      .whenData((l) => l.where((s) => s.porConfirmar).toList()),
);

/// El catálogo de materiales, para elegir qué pedir.
final catalogoTrabajadorProvider = FutureProvider<List<MaterialObra>>(
  (ref) => ref.watch(materialesApiProvider).listar(),
);

/// Todas las herramientas de la empresa, para elegir qué pedir. Las que están
/// en bodega se piden directo; las prestadas o en mantención se ofrecen como
/// pedido especial, para que bodega la consiga cuando vuelva.
final herramientasParaPedirProvider = FutureProvider<List<Herramienta>>((
  ref,
) async {
  final todas = await ref.watch(herramientasApiProvider).listar();
  return todas..sort((a, b) => a.nombre.compareTo(b.nombre));
});

/// Recarga lo del trabajador tras pedir algo: cambian sus pendientes y, si
/// era herramienta, lo que queda disponible.
void recargarTrabajador(WidgetRef ref) {
  ref.invalidate(misSolicitudesProvider);
  ref.invalidate(misPrestamosProvider);
  ref.invalidate(herramientasParaPedirProvider);
}
