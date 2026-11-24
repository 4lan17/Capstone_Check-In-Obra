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
    this.latitud,
    this.longitud,
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

  /// Dónde está la obra. Nulos mientras nadie la marque en el mapa: es un
  /// estado normal —las obras anteriores al mapa no la tienen—, no un error.
  final double? latitud;
  final double? longitud;

  /// Solo con las dos coordenadas hay un lugar que dibujar.
  bool get tieneUbicacion => latitud != null && longitud != null;

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
    latitud: (j['latitud'] as num?)?.toDouble(),
    longitud: (j['longitud'] as num?)?.toDouble(),
  );
}
