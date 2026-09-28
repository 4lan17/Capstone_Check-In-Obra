import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../features/auth/sesion_controller.dart';
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
    String? clave,
  }) => _rest.crear(
    '/api/obras',
    {
      'nombre': nombre,
      'cliente': cliente,
      'ubicacion': ubicacion,
      'jefeTerrenoId': jefeTerrenoId,
    },
    Obra.desdeJson,
    clave: clave,
  );

  /// Asigna o cambia el jefe a cargo. `null` la deja sin jefe.
  Future<Obra> asignarJefe(int obraId, int? jefeTerrenoId, {String? clave}) =>
      _rest.actualizar(
        '/api/obras/$obraId/jefe-terreno',
        {'jefeTerrenoId': jefeTerrenoId},
        Obra.desdeJson,
        clave: clave,
      );

  /// El backend valida antes de cerrar: sin herramientas fuera ni alertas
  /// pendientes. Si no se cumple, responde 409 con el motivo.
  Future<Obra> cerrar(int id, {String? clave}) => _rest.actualizar(
    '/api/obras/$id/cerrar',
    const {},
    Obra.desdeJson,
    clave: clave,
  );
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
    String? clave,
  }) => _rest.crear(
    '/api/materiales',
    {
      'sku': sku,
      'nombre': nombre,
      'categoria': categoria,
      'precioUnitario': precioUnitario,
      'stockMinimo': stockMinimo,
      'codigoBarra': codigoBarra,
    },
    MaterialObra.desdeJson,
    clave: clave,
  );

  Future<MaterialObra> actualizarPrecio(
    int id,
    double nuevoPrecio, {
    String? clave,
  }) => _rest.actualizar(
    '/api/materiales/$id/precio',
    {'nuevoPrecio': nuevoPrecio},
    MaterialObra.desdeJson,
    clave: clave,
  );

  Future<ParametroMerma> definirMerma(
    int materialId,
    double porcentaje, {
    String? clave,
  }) => _rest.actualizar(
    '/api/materiales/$materialId/merma',
    {'porcentaje': porcentaje},
    ParametroMerma.desdeJson,
    clave: clave,
  );
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
    required String tipo,
    required double cantidad,
    int? trabajadorId,
    String? clave,
  }) => _rest.crear(
    '/api/kardex',
    {
      'obraId': obraId,
      'materialId': materialId,
      'trabajadorId': trabajadorId,
      'tipo': tipo,
      'cantidad': cantidad,
    },
    MovimientoKardex.desdeJson,
    clave: clave,
  );
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
    String? clave,
  }) => _rest.crear(
    '/api/herramientas',
    {
      'codigoQr': codigoQr,
      'nombre': nombre,
      'categoria': categoria,
      'valorReposicion': valorReposicion,
    },
    Herramienta.desdeJson,
    clave: clave,
  );
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
    required DateTime fechaDevolEsperada,
    String? clave,
  }) => _rest.crear(
    '/api/prestamos-herramienta',
    {
      'herramientaId': herramientaId,
      'trabajadorId': trabajadorId,
      'obraId': obraId,
      'fechaDevolEsperada': fechaDevolEsperada.toIso8601String(),
    },
    Prestamo.desdeJson,
    clave: clave,
  );

  Future<Prestamo> registrarDevolucion(
    int prestamoId, {
    required String nuevoEstadoHerramienta,
    String? clave,
  }) => _rest.actualizar(
    '/api/prestamos-herramienta/$prestamoId/devolucion',
    {'nuevoEstadoHerramienta': nuevoEstadoHerramienta},
    Prestamo.desdeJson,
    clave: clave,
  );
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

  Future<Alerta> resolver(int alertaId, {String? clave}) => _rest.actualizar(
    '/api/alertas/$alertaId/resolver',
    const {},
    Alerta.desdeJson,
    clave: clave,
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

  Future<Alerta> cerrarTurno({
    required int obraId,
    required String mensaje,
    String? clave,
  }) => _rest.crear(
    '/api/alertas/cierre-turno',
    {'obraId': obraId, 'mensaje': mensaje},
    Alerta.desdeJson,
    clave: clave,
  );
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
    String? clave,
  }) => _rest.crear(
    '/api/usuarios',
    {
      'nombre': nombre,
      'email': email,
      'rut': rut,
      'rol': rol,
      'pinInicial': pinInicial,
    },
    UsuarioEmpresa.desdeJson,
    clave: clave,
  );

  Future<UsuarioEmpresa> redefinirPin(
    int usuarioId,
    String nuevoPin, {
    String? clave,
  }) => _rest.actualizar(
    '/api/usuarios/$usuarioId/pin',
    {'nuevoPin': nuevoPin},
    UsuarioEmpresa.desdeJson,
    clave: clave,
  );
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
/// Quién aprueba o rechaza no viaja en el cuerpo: el backend lo toma del
/// token. Antes se mandaba como `aprobadorId`/`rechazadorId` y el servidor lo
/// creía, así que cualquier bodeguero podía resolver a nombre de otro. Lo
/// mismo vale para `usuarioId` en el kardex y `autorizadorId` en el préstamo.
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
    required double cantidadAEntregar,
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-material/$solicitudId/aprobar',
    {'cantidadAEntregar': cantidadAEntregar},
    MovimientoKardex.desdeJson,
    clave: clave,
  );

  Future<SolicitudMaterial> rechazarMaterial(
    int solicitudId, {
    required String motivo,
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-material/$solicitudId/rechazar',
    {'motivo': motivo},
    SolicitudMaterial.desdeJson,
    clave: clave,
  );

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
    required DateTime fechaDevolEsperada,
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-herramienta/$solicitudId/aprobar',
    {'fechaDevolEsperada': fechaDevolEsperada.toIso8601String()},
    Prestamo.desdeJson,
    clave: clave,
  );

  Future<SolicitudHerramienta> rechazarHerramienta(
    int solicitudId, {
    required String motivo,
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-herramienta/$solicitudId/rechazar',
    {'motivo': motivo},
    SolicitudHerramienta.desdeJson,
    clave: clave,
  );
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
    String? clave,
  }) => _rest.subir(
    '/api/materiales/importar',
    ResultadoImportacion.desdeJson,
    contenido: contenido,
    nombreArchivo: nombreArchivo,
    params: {'confirmar': confirmar},
    clave: clave,
  );

  Future<ResultadoImportacion> herramientas({
    required Uint8List contenido,
    required String nombreArchivo,
    bool confirmar = false,
    String? clave,
  }) => _rest.subir(
    '/api/herramientas/importar',
    ResultadoImportacion.desdeJson,
    contenido: contenido,
    nombreArchivo: nombreArchivo,
    params: {'confirmar': confirmar},
    clave: clave,
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

/// Depende de **quién** entró, no solo del cliente HTTP. Todos los datos de la
/// app cuelgan de acá —catálogo, obras, usuarios, préstamos—, así que cuando
/// cambia la persona se reconstruye la cadena entera. Sin esto, quien entra
/// después en el mismo teléfono veía en caché el catálogo y el padrón del
/// anterior, aunque fuera de otra empresa, hasta tirar para refrescar.
final clienteRestProvider = Provider<ClienteRest>((ref) {
  ref.watch(
    sesionProvider.select(
      (s) => (s.valueOrNull?.usuarioId, s.valueOrNull?.token),
    ),
  );
  return ClienteRest(ref.watch(apiClientProvider));
});

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
