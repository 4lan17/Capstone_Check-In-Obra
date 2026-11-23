import 'package:dio/dio.dart';

import '../../core/network/errores.dart';
import '../../data/api/auth_api.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/codigo_credencial.dart';
import '../../data/modelos/trabajador.dart';

/// Lo que dice el escáner cuando la credencial caducó: es lo que pasa casi
/// siempre que falla, porque el código dura dos minutos.
const mensajeCredencialCaducada =
    'La credencial caducó: pídele al trabajador que la muestre de nuevo.';

/// El resultado de leer una credencial: el trabajador, o por qué no.
typedef ResultadoCredencial = ({Trabajador? trabajador, String? error});

/// Resuelve el código que el bodeguero escaneó o tecleó.
///
/// Acepta el código como lo escriba cualquiera —con guion (`K7M2-9QXP`), en
/// minúsculas o con espacios— y lo lleva a la forma que guarda el servidor.
///
/// Distingue dos fallos que antes eran uno solo:
/// * **409 `CREDENCIAL_CADUCADA`**: el código existió pero venció. No es un
///   error del bodeguero: el trabajador tiene que mostrarlo otra vez.
/// * **404**: no existe, o es de otra constructora —el servidor responde igual
///   a propósito, así que acá tampoco se distingue—.
Future<ResultadoCredencial> buscarTrabajadorPorCredencial(
  TrabajadoresApi api,
  String leido,
) async {
  final codigo = normalizarCodigoCredencial(leido);
  if (codigo.isEmpty) {
    return (
      trabajador: null,
      error: 'Escribe el código que aparece bajo el QR del trabajador.',
    );
  }
  try {
    return (trabajador: await api.porCredencial(codigo), error: null);
  } on ApiException catch (e) {
    if (e.codigo == 'CREDENCIAL_CADUCADA') {
      return (trabajador: null, error: mensajeCredencialCaducada);
    }
    return (
      trabajador: null,
      error: e.statusCode == 404
          ? 'Ese código no corresponde a ningún trabajador de tu empresa. '
                'Revisa que esté bien escrito.'
          : e.mensaje,
    );
  } on DioException catch (e) {
    return (trabajador: null, error: mensajeDeError(e));
  }
}
