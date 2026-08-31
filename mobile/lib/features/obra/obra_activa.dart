import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/obra.dart';

/// Obras activas de la empresa. Las cerradas no se ofrecen: no se puede
/// registrar nada contra una obra cerrada, que es el punto de cerrarla.
final obrasActivasProvider = FutureProvider<List<Obra>>((ref) async {
  final obras = await ref.watch(obrasApiProvider).listar();
  return obras.where((o) => o.activa).toList();
});

/// Todas las obras, incluidas las cerradas — la vista de admin.
final todasLasObrasProvider = FutureProvider<List<Obra>>(
  (ref) => ref.watch(obrasApiProvider).listar(),
);

/// La obra en la que se está trabajando.
///
/// `null` significa que todavía no se elige ninguna, y ese es un estado real:
/// al entrar por primera vez hay que preguntarla antes de poder mostrar stock,
/// herramientas o alertas, porque todas esas cosas son *de una obra*.
class ObraActivaController extends AsyncNotifier<Obra?> {
  @override
  Future<Obra?> build() async {
    final guardada = await ref.read(sesionStorageProvider).leerObraActiva();
    if (guardada == null) return null;

    final obras = await ref.watch(obrasActivasProvider.future);
    // Si la obra guardada se cerró o dejó de existir, se descarta en silencio
    // y se vuelve a preguntar: es preferible a fallar con un 404 opaco.
    return obras.where((o) => o.id == guardada).firstOrNull;
  }

  Future<void> elegir(Obra obra) async {
    await ref.read(sesionStorageProvider).guardarObraActiva(obra.id);
    state = AsyncValue.data(obra);
  }

  Future<void> limpiar() async {
    await ref.read(sesionStorageProvider).olvidarObraActiva();
    state = const AsyncValue.data(null);
  }
}

final obraActivaProvider = AsyncNotifierProvider<ObraActivaController, Obra?>(
  ObraActivaController.new,
);
