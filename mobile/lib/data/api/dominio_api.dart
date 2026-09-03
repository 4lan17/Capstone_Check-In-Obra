import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../modelos/alerta.dart';
import '../modelos/herramienta.dart';
import '../modelos/importacion.dart';
import '../modelos/kardex.dart';
import '../modelos/material.dart';
import '../modelos/obra.dart';
import '../modelos/solicitud.dart';
import '../modelos/trabajador.dart';
import '../modelos/usuario.dart';
import 'cliente_rest.dart';

/// Obras de la empresa. La empresa ya no viaja como parámetro: el backend la
/// saca del token.
class ObrasApi {
  const ObrasApi(this._rest);

  final ClienteRest _rest;

  Future<List<Obra>> listar() => _rest.lista('/api/obras', Obra.desdeJson);

  Future<Obra> obtener(int id) => _rest.uno('/api/obras/$id', Obra.desdeJson);

  Future<Obra> crear({
    required String nombre,
    required String cliente,
    required String ubicacion,
    int? jefeTerrenoId,
  }) => _rest.crear('/api/obras', {
    'nombre': nombre,
    'cliente': cliente,
    'ubicacion': ubicacion,
    'jefeTerrenoId': jefeTerrenoId,
  }, Obra.desdeJson);

  /// Asigna o cambia el jefe a cargo. `null` la deja sin jefe.
  Future<Obra> asignarJefe(int obraId, int? jefeTerrenoId) => _rest.actualizar(
    '/api/obras/$obraId/jefe-terreno',
    {'jefeTerrenoId': jefeTerrenoId},
    Obra.desdeJson,
  );

  /// El backend valida antes de cerrar: sin herramientas fuera ni alertas
  /// pendientes. Si no se cumple, responde 409 con el motivo.
  Future<Obra> cerrar(int id) =>
      _rest.actualizar('/api/obras/$id/cerrar', const {}, Obra.desdeJson);
}

class MaterialesApi {
  const MaterialesApi(this._rest);

  final ClienteRest _rest;

  Future<List<MaterialObra>> listar({String? categoria}) => _rest.lista(
    '/api/materiales',
    MaterialObra.desdeJson,
    params: categoria == null ? null : {'categoria': categoria},
  );

  Future<MaterialObra> obtener(int id) =>
      _rest.uno('/api/materiales/$id', MaterialObra.desdeJson);

  /// Lo que resuelve el escáner de código de barras: el backend prueba el
  /// código impreso de fábrica y después el SKU, porque quien apunta la cámara
  /// a una etiqueta no sabe cuál de los dos está leyendo.
  Future<MaterialObra> porCodigo(String codigo) => _rest.uno(
    '/api/materiales/por-codigo/${Uri.encodeComponent(codigo)}',
    MaterialObra.desdeJson,
  );

  Future<MaterialObra> crear({
    required String sku,
    required String nombre,
    required String categoria,
    required double precioUnitario,
    required double stockMinimo,
    String? codigoBarra,
  }) => _rest.crear('/api/materiales', {
    'sku': sku,
    'nombre': nombre,
    'categoria': categoria,
    'precioUnitario': precioUnitario,
    'stockMinimo': stockMinimo,
    'codigoBarra': codigoBarra,
  }, MaterialObra.desdeJson);

  Future<MaterialObra> actualizarPrecio(int id, double nuevoPrecio) =>
      _rest.actualizar('/api/materiales/$id/precio', {
        'nuevoPrecio': nuevoPrecio,
      }, MaterialObra.desdeJson);

  Future<ParametroMerma> definirMerma(int materialId, double porcentaje) =>
      _rest.actualizar('/api/materiales/$materialId/merma', {
        'porcentaje': porcentaje,
      }, ParametroMerma.desdeJson);
}

class KardexApi {
  const KardexApi(this._rest);

  final ClienteRest _rest;

  Future<List<MovimientoKardex>> porObra(int obraId) => _rest.lista(
    '/api/kardex',
    MovimientoKardex.desdeJson,
    params: {'obraId': obraId},
  );

  /// El stock es la suma con signo de los movimientos, no una columna.
  Future<double> stock({required int obraId, required int materialId}) =>
      _rest.numero(
        '/api/kardex/stock',
        params: {'obraId': obraId, 'materialId': materialId},
      );

  /// Devuelve 409 si un DESPACHO o CONSUMO dejaría el saldo negativo.
  /// `trabajadorId` es obligatorio en un DESPACHO —hay que saber a quién se le
  /// entregó— y el backend lo rechaza en una RECEPCION.
  Future<MovimientoKardex> registrar({
    required int obraId,
    required int materialId,
    required int usuarioId,
    required String tipo,
    required double cantidad,
    int? trabajadorId,
  }) => _rest.crear('/api/kardex', {
    'obraId': obraId,
    'materialId': materialId,
    'usuarioId': usuarioId,
    'trabajadorId': trabajadorId,
    'tipo': tipo,
    'cantidad': cantidad,
  }, MovimientoKardex.desdeJson);
}

class HerramientasApi {
  const HerramientasApi(this._rest);

  final ClienteRest _rest;

  Future<List<Herramienta>> listar() =>
      _rest.lista('/api/herramientas', Herramienta.desdeJson);

  /// Lo que resuelve el escaneo de QR.
  /// El código va codificado: el ingreso manual del escáner acepta cualquier
  /// texto, y un "/" partiría la ruta en dos segmentos —405 en vez de "código
  /// no reconocido"— mientras que un "?" o un "#" la truncarían.
  Future<Herramienta> porCodigo(String codigoQr) => _rest.uno(
    '/api/herramientas/por-codigo/${Uri.encodeComponent(codigoQr)}',
    Herramienta.desdeJson,
  );

  Future<Herramienta> crear({
    required String codigoQr,
    required String nombre,
    required String categoria,
    required double valorReposicion,
  }) => _rest.crear('/api/herramientas', {
    'codigoQr': codigoQr,
    'nombre': nombre,
    'categoria': categoria,
    'valorReposicion': valorReposicion,
  }, Herramienta.desdeJson);
}

class PrestamosApi {
  const PrestamosApi(this._rest);

  final ClienteRest _rest;

  Future<List<Prestamo>> porObra(int obraId) => _rest.lista(
    '/api/prestamos-herramienta',
    Prestamo.desdeJson,
    params: {'obraId': obraId},
  );

  Future<List<Prestamo>> vencidos() => _rest.lista(
    '/api/prestamos-herramienta',
    Prestamo.desdeJson,
    params: {'soloVencidos': true},
  );

  /// Préstamo directo del bodeguero, sin pasar por una solicitud previa.
  Future<Prestamo> prestar({
    required int herramientaId,
    required int trabajadorId,
    required int obraId,
    required int autorizadorId,
    required DateTime fechaDevolEsperada,
  }) => _rest.crear('/api/prestamos-herramienta', {
    'herramientaId': herramientaId,
    'trabajadorId': trabajadorId,
    'obraId': obraId,
    'autorizadorId': autorizadorId,
    'fechaDevolEsperada': fechaDevolEsperada.toIso8601String(),
  }, Prestamo.desdeJson);

  Future<Prestamo> registrarDevolucion(
    int prestamoId, {
    required String nuevoEstadoHerramienta,
  }) => _rest.actualizar('/api/prestamos-herramienta/$prestamoId/devolucion', {
    'nuevoEstadoHerramienta': nuevoEstadoHerramienta,
  }, Prestamo.desdeJson);
}

class AlertasApi {
  const AlertasApi(this._rest);

  final ClienteRest _rest;

  Future<List<Alerta>> porObra(int obraId, {bool soloSinResolver = false}) =>
      _rest.lista(
        '/api/alertas',
        Alerta.desdeJson,
        params: {'obraId': obraId, 'soloSinResolver': soloSinResolver},
      );

  Future<Alerta> resolver(int alertaId) => _rest.actualizar(
    '/api/alertas/$alertaId/resolver',
    const {},
    Alerta.desdeJson,
  );

  /// Barre la obra y crea las alertas que correspondan. Se dispara al abrir
  /// Alertas y al cerrar turno: el backend no tiene tareas programadas.
  Future<List<Alerta>> detectarNoDevueltas(int obraId) => _rest.crearLista(
    '/api/alertas/detectar-no-devueltas?obraId=$obraId',
    const {},
    Alerta.desdeJson,
  );

  Future<List<Alerta>> detectarStockCritico(int obraId) => _rest.crearLista(
    '/api/alertas/detectar-stock-critico?obraId=$obraId',
    const {},
    Alerta.desdeJson,
  );

  Future<Alerta> cerrarTurno({required int obraId, required String mensaje}) =>
      _rest.crear('/api/alertas/cierre-turno', {
        'obraId': obraId,
        'mensaje': mensaje,
      }, Alerta.desdeJson);
}

class UsuariosApi {
  const UsuariosApi(this._rest);

  final ClienteRest _rest;

  Future<List<UsuarioEmpresa>> listar() =>
      _rest.lista('/api/usuarios', UsuarioEmpresa.desdeJson);

  Future<UsuarioEmpresa> crear({
    required String nombre,
    required String email,
    required String rut,
    required String rol,
    required String pinInicial,
  }) => _rest.crear('/api/usuarios', {
    'nombre': nombre,
    'email': email,
    'rut': rut,
    'rol': rol,
    'pinInicial': pinInicial,
  }, UsuarioEmpresa.desdeJson);

  Future<UsuarioEmpresa> redefinirPin(int usuarioId, String nuevoPin) =>
      _rest.actualizar('/api/usuarios/$usuarioId/pin', {
        'nuevoPin': nuevoPin,
      }, UsuarioEmpresa.desdeJson);
}

class TrabajadoresApi {
  const TrabajadoresApi(this._rest);

  final ClienteRest _rest;

  /// Los trabajadores de una obra. El backend los alcanza por la cuadrilla, así
  /// que un trabajador sin cuadrilla asignada no aparece en ninguna obra.
  Future<List<Trabajador>> porObra(int obraId) => _rest.lista(
    '/api/trabajadores',
    Trabajador.desdeJson,
    params: {'obraId': obraId},
  );

  Future<Trabajador> porCredencial(String credencialQr) => _rest.uno(
    '/api/trabajadores/por-credencial/${Uri.encodeComponent(credencialQr)}',
    Trabajador.desdeJson,
  );
}

/// Las solicitudes que el trabajador levanta y el bodeguero resuelve.
///
/// Aprobar no devuelve la solicitud: devuelve lo que la solicitud produjo —un
/// movimiento de kardex si era material, un préstamo si era herramienta—.
/// Es la forma del backend y conviene respetarla, porque es lo que hay que
/// mostrar después de aprobar.
class SolicitudesApi {
  const SolicitudesApi(this._rest);

  final ClienteRest _rest;

  Future<List<SolicitudMaterial>> materialesPorObra(
    int obraId, {
    bool soloPendientes = true,
  }) => _rest.lista(
    '/api/solicitudes-material',
    SolicitudMaterial.desdeJson,
    params: {'obraId': obraId, 'soloPendientes': soloPendientes},
  );

  /// Todo lo que pidió un trabajador, resuelto o no. Es lo que se consulta tras
  /// escanear su credencial.
  Future<List<SolicitudMaterial>> materialesPorTrabajador(int trabajadorId) =>
      _rest.lista(
        '/api/solicitudes-material',
        SolicitudMaterial.desdeJson,
        params: {'trabajadorId': trabajadorId},
      );

  /// `cantidadAEntregar` puede ser menor que la pedida: si no hay tanto en
  /// bodega, se entrega lo que hay. El backend rechaza con 409 lo que dejaría
  /// el saldo negativo.
  Future<MovimientoKardex> aprobarMaterial(
    int solicitudId, {
    required int aprobadorId,
    required double cantidadAEntregar,
  }) => _rest.actualizar('/api/solicitudes-material/$solicitudId/aprobar', {
    'aprobadorId': aprobadorId,
    'cantidadAEntregar': cantidadAEntregar,
  }, MovimientoKardex.desdeJson);

  Future<SolicitudMaterial> rechazarMaterial(
    int solicitudId, {
    required int rechazadorId,
    required String motivo,
  }) => _rest.actualizar('/api/solicitudes-material/$solicitudId/rechazar', {
    'rechazadorId': rechazadorId,
    'motivo': motivo,
  }, SolicitudMaterial.desdeJson);

  Future<List<SolicitudHerramienta>> herramientasPorObra(
    int obraId, {
    bool soloPendientes = true,
  }) => _rest.lista(
    '/api/solicitudes-herramienta',
    SolicitudHerramienta.desdeJson,
    params: {'obraId': obraId, 'soloPendientes': soloPendientes},
  );

  Future<List<SolicitudHerramienta>> herramientasPorTrabajador(
    int trabajadorId,
  ) => _rest.lista(
    '/api/solicitudes-herramienta',
    SolicitudHerramienta.desdeJson,
    params: {'trabajadorId': trabajadorId},
  );

  /// Aprobar genera el préstamo, así que la fecha de devolución esperada es
  /// obligatoria: es la que después vence y dispara la alerta.
  Future<Prestamo> aprobarHerramienta(
    int solicitudId, {
    required int aprobadorId,
    required DateTime fechaDevolEsperada,
  }) => _rest.actualizar('/api/solicitudes-herramienta/$solicitudId/aprobar', {
    'aprobadorId': aprobadorId,
    'fechaDevolEsperada': fechaDevolEsperada.toIso8601String(),
  }, Prestamo.desdeJson);

  Future<SolicitudHerramienta> rechazarHerramienta(
    int solicitudId, {
    required int rechazadorId,
    required String motivo,
  }) => _rest.actualizar('/api/solicitudes-herramienta/$solicitudId/rechazar', {
    'rechazadorId': rechazadorId,
    'motivo': motivo,
  }, SolicitudHerramienta.desdeJson);
}

/// Alta masiva de catálogo desde una planilla Excel.
///
/// Se llama dos veces con el mismo archivo: primero sin confirmar —para ver el
/// informe— y después confirmando. No es una llamada de más: es lo que evita
/// cargar un catálogo a ciegas y descubrir el error cuando ya está adentro.
class ImportacionApi {
  const ImportacionApi(this._rest);

  final ClienteRest _rest;

  Future<ResultadoImportacion> materiales({
    required Uint8List contenido,
    required String nombreArchivo,
    bool confirmar = false,
  }) => _rest.subir(
    '/api/materiales/importar',
    ResultadoImportacion.desdeJson,
    contenido: contenido,
    nombreArchivo: nombreArchivo,
    params: {'confirmar': confirmar},
  );

  Future<ResultadoImportacion> herramientas({
    required Uint8List contenido,
    required String nombreArchivo,
    bool confirmar = false,
  }) => _rest.subir(
    '/api/herramientas/importar',
    ResultadoImportacion.desdeJson,
    contenido: contenido,
    nombreArchivo: nombreArchivo,
    params: {'confirmar': confirmar},
  );

  /// La planilla vacía con las columnas en el orden que espera el servidor.
  /// Se descarga antes de llenarla: el lector va por posición, no por el
  /// nombre del encabezado.
  Future<Uint8List> plantillaDeMateriales() =>
      _rest.descargar('/api/materiales/plantilla-importacion');

  Future<Uint8List> plantillaDeHerramientas() =>
      _rest.descargar('/api/herramientas/plantilla-importacion');
}

class EmpresaApi {
  const EmpresaApi(this._rest);

  final ClienteRest _rest;

  Future<Empresa> mia() => _rest.uno('/api/empresas/mia', Empresa.desdeJson);
}

// --- Providers ---------------------------------------------------------------

final clienteRestProvider = Provider<ClienteRest>(
  (ref) => ClienteRest(ref.watch(apiClientProvider)),
);

final obrasApiProvider = Provider(
  (ref) => ObrasApi(ref.watch(clienteRestProvider)),
);
final materialesApiProvider = Provider(
  (ref) => MaterialesApi(ref.watch(clienteRestProvider)),
);
final kardexApiProvider = Provider(
  (ref) => KardexApi(ref.watch(clienteRestProvider)),
);
final herramientasApiProvider = Provider(
  (ref) => HerramientasApi(ref.watch(clienteRestProvider)),
);
final prestamosApiProvider = Provider(
  (ref) => PrestamosApi(ref.watch(clienteRestProvider)),
);
final alertasApiProvider = Provider(
  (ref) => AlertasApi(ref.watch(clienteRestProvider)),
);
final usuariosApiProvider = Provider(
  (ref) => UsuariosApi(ref.watch(clienteRestProvider)),
);
final trabajadoresApiProvider = Provider(
  (ref) => TrabajadoresApi(ref.watch(clienteRestProvider)),
);
final empresaApiProvider = Provider(
  (ref) => EmpresaApi(ref.watch(clienteRestProvider)),
);
final solicitudesApiProvider = Provider(
  (ref) => SolicitudesApi(ref.watch(clienteRestProvider)),
);
final importacionApiProvider = Provider(
  (ref) => ImportacionApi(ref.watch(clienteRestProvider)),
);
