// Respuestas de ejemplo de los tres endpoints de métricas, con el contrato
// ajustado de backend. Las usan los tests de modelos y de pantallas.

/// El contrato de Jefe, con los ajustes de backend: sin `porPartida` y con
/// `otros`.
Map<String, dynamic> jefeJson({
  List<Map<String, dynamic>>? porMaterial,
  Map<String, dynamic>? otros,
  Object? umbralPct = 10.0,
}) => {
  'gastoAcumulado': {
    'presupuestoTotal': 48200000.0,
    'ejecutadoTotal': 52300000.0,
    'serie': [
      {
        'etiqueta': 'S1',
        'desde': '2026-10-05',
        'ejecutadoAcumulado': 8000000.0,
      },
      {
        'etiqueta': 'S2',
        'desde': '2026-10-12',
        'ejecutadoAcumulado': 21000000.0,
      },
      {
        'etiqueta': 'S3',
        'desde': '2026-10-19',
        'ejecutadoAcumulado': 52300000.0,
      },
    ],
  },
  'porMaterial':
      porMaterial ??
      [
        materialJson(1, 'Volcanita ST', 11800000, 13500000, 14.4, true),
        materialJson(2, 'Metalcom', 9600000, 10300000, 7.3, false),
        materialJson(3, 'Pino bruto', 7200000, 7400000, 2.8, false),
        materialJson(4, 'Aislante', 5100000, 4900000, -3.9, false),
        materialJson(5, 'Clavos', 1000000, 1100000, null, false),
      ],
  'otros': otros ?? {'cantidad': 12, 'ejecutado': 15100000.0},
  'umbralPct': umbralPct,
};

Map<String, dynamic> materialJson(
  int id,
  String nombre,
  double presupuestado,
  double ejecutado,
  double? pct,
  bool supera,
) => {
  'materialId': id,
  'sku': 'SKU-$id',
  'nombre': nombre,
  'presupuestado': presupuestado,
  'ejecutado': ejecutado,
  'desviacionPct': pct,
  'superaUmbral': supera,
};

Map<String, dynamic> bodegaJson() => {
  'granularidad': 'DIA',
  'movimientos': [
    {'fecha': '2026-11-16', 'recepcion': 3, 'despacho': 8, 'consumo': 2},
    {'fecha': '2026-11-17', 'recepcion': 0, 'despacho': 5, 'consumo': 1},
    {'fecha': '2026-11-18', 'recepcion': 4, 'despacho': 3, 'consumo': 3},
  ],
  'masDespachados': [
    {
      'materialId': 1,
      'sku': 'TAB-VOL-ST-10',
      'nombre': 'Volcanita ST 10 mm',
      'cantidad': 142.0,
    },
    {
      'materialId': 2,
      'sku': 'MET-M90',
      'nombre': 'Montante 90',
      'cantidad': 96.0,
    },
  ],
  'herramientasPorEstado': {
    'DISPONIBLE': 21,
    'PRESTADA': 17,
    'MANTENCION': 2,
    'NO_DEVUELTA': 2,
  },
  'totalHerramientas': 42,
  'prestadasEnEstaObra': 6,
};

Map<String, dynamic> empresaJson() => {
  'alertasPorSemana': [
    {'etiqueta': 'S7', 'desde': '2026-11-02', 'generadas': 6, 'resueltas': 5},
    {'etiqueta': 'S8', 'desde': '2026-11-09', 'generadas': 9, 'resueltas': 8},
  ],
  'desviacionPorObra': [
    {'obraId': 1, 'nombre': 'Torre B', 'desviacionPct': 8.4},
    {'obraId': 2, 'nombre': 'Torre C', 'desviacionPct': 2.1},
    {'obraId': 3, 'nombre': 'Parque Los Robles', 'desviacionPct': -1.5},
    {'obraId': 4, 'nombre': 'Sin presupuesto', 'desviacionPct': null},
  ],
  'umbralPct': 5.0,
  'usuariosPorRol': {
    'TRABAJADOR': 11,
    'BODEGUERO': 6,
    'JEFE_TERRENO': 4,
    'ADMIN': 2,
  },
  'obrasPorEstado': {'ACTIVA': 3, 'CERRADA': 1},
};
