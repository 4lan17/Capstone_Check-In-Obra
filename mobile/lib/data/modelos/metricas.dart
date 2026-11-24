// Las métricas de cada rol (`GET …/metricas/…?periodo=`).
//
// Todos los modelos **toleran lo que falte**: campos ausentes, listas vacías,
// porcentajes nulos. Una métrica sin datos es un estado normal —una obra
// recién creada no tiene gasto—, no un error.

/// El periodo que se mira: 7 días, 30 días o toda la obra.
enum PeriodoMetricas {
  sieteDias('7d', '7 días'),
  treintaDias('30d', '30 días'),
  todaLaObra('obra', 'Toda la obra');

  const PeriodoMetricas(this.codigo, this.etiqueta);

  /// Lo que se manda en `?periodo=`.
  final String codigo;
  final String etiqueta;
}

double _numero(Object? v) => (v as num?)?.toDouble() ?? 0;

int _entero(Object? v) => (v as num?)?.toInt() ?? 0;

DateTime? _fecha(Object? v) => v is String ? DateTime.tryParse(v) : null;

List<T> _lista<T>(Object? v, T Function(Map<String, dynamic>) leer) => [
  for (final e in (v as List<dynamic>? ?? const []))
    if (e is Map<String, dynamic>) leer(e),
];

Map<String, int> _conteos(Object? v) => {
  for (final e in (v as Map<String, dynamic>? ?? const {}).entries)
    e.key: _entero(e.value),
};

/// Una parte de una dona: una etiqueta, cuánto vale y qué fracción del total.
class ParteDeDona {
  const ParteDeDona({
    required this.etiqueta,
    required this.valor,
    required this.proporcion,
  });

  final String etiqueta;
  final double valor;

  /// De 0 a 1.
  final double proporcion;
}

// --- Jefe de terreno ---------------------------------------------------------

/// `GET /api/obras/{id}/metricas/jefe`.
/// Cómo se llama la parte de la dona que junta a los materiales menores.
const etiquetaOtrosMateriales = 'Otros materiales';

class MetricasJefe {
  const MetricasJefe({
    required this.gastoAcumulado,
    required this.porMaterial,
    required this.otros,
    required this.umbralPct,
  });

  final GastoAcumulado gastoAcumulado;

  /// Los materiales de mayor gasto (hasta 5), con su desviación.
  final List<GastoMaterial> porMaterial;

  /// Lo que suma el resto de los materiales, que no entran en [porMaterial].
  final OtrosMateriales otros;

  /// Desde cuántos puntos de desviación se da la alerta.
  final double? umbralPct;

  factory MetricasJefe.desdeJson(Map<String, dynamic> j) => MetricasJefe(
    gastoAcumulado: GastoAcumulado.desdeJson(
      j['gastoAcumulado'] as Map<String, dynamic>? ?? const {},
    ),
    porMaterial: _lista(j['porMaterial'], GastoMaterial.desdeJson),
    otros: OtrosMateriales.desdeJson(
      j['otros'] as Map<String, dynamic>? ?? const {},
    ),
    umbralPct: (j['umbralPct'] as num?)?.toDouble(),
  );

  /// El material con mayor desviación porcentual; `null` si ninguno tiene
  /// porcentaje (todos consumidos sin presupuestar).
  GastoMaterial? get masPasado {
    GastoMaterial? mayor;
    for (final m in porMaterial) {
      final pct = m.desviacionPct;
      if (pct == null) continue;
      if (mayor == null || pct > mayor.desviacionPct!) mayor = m;
    }
    return mayor;
  }

  /// La dona «Ejecutado por material»: los cuatro mayores y «Otros materiales»
  /// (el quinto más todo el resto). Nunca más de cinco partes.
  List<ParteDeDona> get partesDeDona {
    final ordenados = [...porMaterial]
      ..sort((a, b) => b.ejecutado.compareTo(a.ejecutado));
    final principales = ordenados.take(4).toList();
    final resto =
        ordenados.skip(4).fold<double>(0, (s, m) => s + m.ejecutado) +
        otros.ejecutado;
    final valores = <(String, double)>[
      for (final m in principales) (m.nombre, m.ejecutado),
      if (resto > 0) (etiquetaOtrosMateriales, resto),
    ];
    final total = valores.fold<double>(0, (s, v) => s + v.$2);
    if (total <= 0) return const [];
    return [
      for (final (nombre, valor) in valores)
        ParteDeDona(etiqueta: nombre, valor: valor, proporcion: valor / total),
    ];
  }

  /// Lo que suman las partes de la dona.
  double get totalPartes => partesDeDona.fold<double>(0, (s, p) => s + p.valor);

  /// Sin gasto que mostrar: ni serie, ni materiales.
  bool get estaVacio =>
      gastoAcumulado.serie.isEmpty &&
      gastoAcumulado.ejecutadoTotal == 0 &&
      porMaterial.isEmpty &&
      otros.ejecutado == 0;
}

class GastoAcumulado {
  const GastoAcumulado({
    required this.presupuestoTotal,
    required this.ejecutadoTotal,
    required this.serie,
  });

  final double presupuestoTotal;
  final double ejecutadoTotal;
  final List<PuntoDeGasto> serie;

  /// Sin presupuesto no hay contra qué pasarse.
  bool get superaPresupuesto =>
      presupuestoTotal > 0 && ejecutadoTotal > presupuestoTotal;

  factory GastoAcumulado.desdeJson(Map<String, dynamic> j) => GastoAcumulado(
    presupuestoTotal: _numero(j['presupuestoTotal']),
    ejecutadoTotal: _numero(j['ejecutadoTotal']),
    serie: _lista(j['serie'], PuntoDeGasto.desdeJson),
  );
}

class PuntoDeGasto {
  const PuntoDeGasto({
    required this.etiqueta,
    required this.desde,
    required this.ejecutadoAcumulado,
  });

  final String etiqueta;
  final DateTime? desde;
  final double ejecutadoAcumulado;

  factory PuntoDeGasto.desdeJson(Map<String, dynamic> j) => PuntoDeGasto(
    etiqueta: j['etiqueta'] as String? ?? '',
    desde: _fecha(j['desde']),
    ejecutadoAcumulado: _numero(j['ejecutadoAcumulado']),
  );
}

class GastoMaterial {
  const GastoMaterial({
    required this.materialId,
    required this.sku,
    required this.nombre,
    required this.presupuestado,
    required this.ejecutado,
    required this.desviacionPct,
    required this.superaUmbral,
  });

  final int materialId;
  final String sku;
  final String nombre;
  final double presupuestado;
  final double ejecutado;

  /// `null` si se consumió sin estar presupuestado.
  final double? desviacionPct;
  final bool superaUmbral;

  factory GastoMaterial.desdeJson(Map<String, dynamic> j) => GastoMaterial(
    materialId: _entero(j['materialId']),
    sku: j['sku'] as String? ?? '',
    nombre: j['nombre'] as String? ?? '',
    presupuestado: _numero(j['presupuestado']),
    ejecutado: _numero(j['ejecutado']),
    desviacionPct: (j['desviacionPct'] as num?)?.toDouble(),
    superaUmbral: j['superaUmbral'] as bool? ?? false,
  );
}

class OtrosMateriales {
  const OtrosMateriales({required this.cantidad, required this.ejecutado});

  /// Cuántos materiales son.
  final int cantidad;
  final double ejecutado;

  factory OtrosMateriales.desdeJson(Map<String, dynamic> j) => OtrosMateriales(
    cantidad: _entero(j['cantidad']),
    ejecutado: _numero(j['ejecutado']),
  );
}

// --- Bodega --------------------------------------------------------------------

/// `GET /api/obras/{id}/metricas/bodega`.
class MetricasBodega {
  const MetricasBodega({
    required this.granularidad,
    required this.movimientos,
    required this.masDespachados,
    required this.herramientasPorEstado,
    required this.totalHerramientas,
    required this.prestadasEnEstaObra,
  });

  /// De qué tamaño es cada punto de [movimientos]: `DIA`, `SEMANA` o `MES`.
  final String granularidad;
  final List<MovimientosDelDia> movimientos;
  final List<MaterialDespachado> masDespachados;

  /// Las herramientas son **de la empresa** (no tienen obra): este conteo es
  /// de todas.
  final Map<String, int> herramientasPorEstado;
  final int totalHerramientas;

  /// Cuántas de las prestadas están en esta obra.
  final int prestadasEnEstaObra;

  factory MetricasBodega.desdeJson(Map<String, dynamic> j) => MetricasBodega(
    granularidad: j['granularidad'] as String? ?? 'DIA',
    movimientos: _lista(j['movimientos'], MovimientosDelDia.desdeJson),
    masDespachados: _lista(j['masDespachados'], MaterialDespachado.desdeJson),
    herramientasPorEstado: _conteos(j['herramientasPorEstado']),
    totalHerramientas: _entero(j['totalHerramientas']),
    prestadasEnEstaObra: _entero(j['prestadasEnEstaObra']),
  );

  int get totalSalidas => movimientos.fold(0, (s, m) => s + m.salidas);

  int get totalEntradas => movimientos.fold(0, (s, m) => s + m.entradas);

  bool get sinMovimientos => totalSalidas + totalEntradas == 0;
}

class MovimientosDelDia {
  const MovimientosDelDia({
    required this.fecha,
    required this.recepcion,
    required this.despacho,
    required this.consumo,
  });

  final DateTime? fecha;
  final int recepcion;
  final int despacho;
  final int consumo;

  /// Lo que sale de bodega: despacho y consumo.
  int get salidas => despacho + consumo;

  /// Lo que entra: recepción.
  int get entradas => recepcion;

  factory MovimientosDelDia.desdeJson(Map<String, dynamic> j) =>
      MovimientosDelDia(
        fecha: _fecha(j['fecha']),
        recepcion: _entero(j['recepcion']),
        despacho: _entero(j['despacho']),
        consumo: _entero(j['consumo']),
      );
}

class MaterialDespachado {
  const MaterialDespachado({
    required this.materialId,
    required this.sku,
    required this.nombre,
    required this.cantidad,
  });

  final int materialId;
  final String sku;
  final String nombre;
  final double cantidad;

  factory MaterialDespachado.desdeJson(Map<String, dynamic> j) =>
      MaterialDespachado(
        materialId: _entero(j['materialId']),
        sku: j['sku'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        cantidad: _numero(j['cantidad']),
      );
}

// --- Administrador -------------------------------------------------------------

/// `GET /api/metricas/empresa`.
class MetricasEmpresa {
  const MetricasEmpresa({
    required this.alertasPorSemana,
    required this.desviacionPorObra,
    required this.umbralPct,
    required this.usuariosPorRol,
    required this.obrasPorEstado,
  });

  final List<AlertasDeLaSemana> alertasPorSemana;
  final List<DesviacionDeObra> desviacionPorObra;

  /// El umbral de desviación de la empresa.
  final double? umbralPct;

  /// Cuenta **todos** los usuarios.
  final Map<String, int> usuariosPorRol;
  final Map<String, int> obrasPorEstado;

  factory MetricasEmpresa.desdeJson(Map<String, dynamic> j) => MetricasEmpresa(
    alertasPorSemana: _lista(
      j['alertasPorSemana'],
      AlertasDeLaSemana.desdeJson,
    ),
    desviacionPorObra: _lista(
      j['desviacionPorObra'],
      DesviacionDeObra.desdeJson,
    ),
    umbralPct: (j['umbralPct'] as num?)?.toDouble(),
    usuariosPorRol: _conteos(j['usuariosPorRol']),
    obrasPorEstado: _conteos(j['obrasPorEstado']),
  );

  /// La obra con mayor desviación porcentual.
  DesviacionDeObra? get masDesviada {
    DesviacionDeObra? mayor;
    for (final o in desviacionPorObra) {
      final pct = o.desviacionPct;
      if (pct == null) continue;
      if (mayor == null || pct > mayor.desviacionPct!) mayor = o;
    }
    return mayor;
  }

  int get totalUsuarios => usuariosPorRol.values.fold(0, (s, n) => s + n);

  bool get sinAlertas =>
      alertasPorSemana.every((s) => s.generadas == 0 && s.resueltas == 0);
}

class AlertasDeLaSemana {
  const AlertasDeLaSemana({
    required this.etiqueta,
    required this.desde,
    required this.generadas,
    required this.resueltas,
  });

  final String etiqueta;
  final DateTime? desde;
  final int generadas;

  /// De las generadas esa semana, cuántas están resueltas **hasta hoy**: una
  /// cohorte, no lo que se resolvió esa semana.
  final int resueltas;

  factory AlertasDeLaSemana.desdeJson(Map<String, dynamic> j) =>
      AlertasDeLaSemana(
        etiqueta: j['etiqueta'] as String? ?? '',
        desde: _fecha(j['desde']),
        generadas: _entero(j['generadas']),
        resueltas: _entero(j['resueltas']),
      );
}

class DesviacionDeObra {
  const DesviacionDeObra({
    required this.obraId,
    required this.nombre,
    required this.desviacionPct,
  });

  final int obraId;
  final String nombre;

  /// `null` si la obra no tiene presupuesto contra el cual medirse.
  final double? desviacionPct;

  bool get sinPresupuesto => desviacionPct == null;

  bool superaUmbral(double? umbralPct) =>
      desviacionPct != null && umbralPct != null && desviacionPct! > umbralPct;

  factory DesviacionDeObra.desdeJson(Map<String, dynamic> j) =>
      DesviacionDeObra(
        obraId: _entero(j['obraId']),
        nombre: j['nombre'] as String? ?? '',
        desviacionPct: (j['desviacionPct'] as num?)?.toDouble(),
      );
}
