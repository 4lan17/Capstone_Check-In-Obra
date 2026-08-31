/// Refleja `ObraResponse` del backend.
class Obra {
  const Obra({
    required this.id,
    required this.nombre,
    required this.cliente,
    required this.ubicacion,
    required this.estado,
    required this.jefeTerrenoNombre,
    required this.jefeTerrenoRut,
  });

  final int id;
  final String nombre;
  final String cliente;
  final String ubicacion;

  /// `EstadoObra`: ACTIVA o CERRADA.
  final String estado;

  /// Quién dirige la obra. Nulos mientras no se le asigne jefe — que es un
  /// estado real, no un dato que falte.
  final String? jefeTerrenoNombre;
  final String? jefeTerrenoRut;

  bool get tieneJefe => jefeTerrenoNombre != null;

  String get jefeIdentificacion => jefeTerrenoNombre == null
      ? 'Sin jefe asignado'
      : jefeTerrenoRut == null
      ? jefeTerrenoNombre!
      : '$jefeTerrenoNombre · $jefeTerrenoRut';

  bool get activa => estado == 'ACTIVA';

  factory Obra.desdeJson(Map<String, dynamic> j) => Obra(
    id: j['id'] as int,
    nombre: j['nombre'] as String,
    cliente: j['cliente'] as String,
    ubicacion: j['ubicacion'] as String,
    estado: j['estado'] as String,
    jefeTerrenoNombre: j['jefeTerrenoNombre'] as String?,
    jefeTerrenoRut: j['jefeTerrenoRut'] as String?,
  );
}
