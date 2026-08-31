/// Refleja `AlertaResponse` del backend.
class Alerta {
  const Alerta({
    required this.id,
    required this.tipo,
    required this.mensaje,
    required this.fecha,
    required this.resuelto,
  });

  final int id;

  /// `TipoAlerta`: NO_DEVUELTA, STOCK_CRITICO o CIERRE_TURNO.
  final String tipo;
  final String mensaje;
  final DateTime fecha;
  final bool resuelto;

  factory Alerta.desdeJson(Map<String, dynamic> j) => Alerta(
    id: j['id'] as int,
    tipo: j['tipo'] as String,
    mensaje: j['mensaje'] as String,
    fecha: DateTime.parse(j['fecha'] as String),
    resuelto: j['resuelto'] as bool,
  );
}

/// Nombre legible de cada `TipoAlerta`, para el chip de la lista.
String nombreDeAlerta(String tipo) => switch (tipo) {
  'NO_DEVUELTA' => 'No devuelta',
  'STOCK_CRITICO' => 'Stock crítico',
  'CIERRE_TURNO' => 'Cierre de turno',
  _ => tipo,
};
