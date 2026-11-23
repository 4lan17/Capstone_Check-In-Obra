/// Refleja `GET /api/presupuestos/{id}/desviacion`: lo presupuestado contra lo
/// ejecutado en bodega, en total y por material.
class Desviacion {
  const Desviacion({
    required this.desviacionPct,
    required this.mermaRealVsEstimada,
    required this.presupuestado,
    required this.ejecutado,
    required this.desviacionMonto,
    required this.umbralPct,
    required this.superaUmbral,
    required this.materiales,
  });

  /// (ejecutado − presupuestado) / presupuestado × 100. `null` si no hay
  /// presupuesto contra qué medir.
  final double? desviacionPct;

  /// Merma real promedio menos la merma con que se cubicó, en puntos
  /// porcentuales. `null` si ningún material tiene cubicación.
  final double? mermaRealVsEstimada;
  final double presupuestado;
  final double ejecutado;
  final double desviacionMonto;

  /// Desde cuántos puntos de desviación se da la alerta.
  final double? umbralPct;
  final bool superaUmbral;

  /// Ordenados por |desviacionMonto|, de mayor a menor: arriba lo que más pesa.
  final List<DesviacionMaterial> materiales;

  factory Desviacion.desdeJson(Map<String, dynamic> j) {
    final presupuestado = (j['presupuestado'] as num).toDouble();
    final ejecutado = (j['ejecutado'] as num).toDouble();
    return Desviacion(
      desviacionPct: (j['desviacionPct'] as num?)?.toDouble(),
      mermaRealVsEstimada: (j['mermaRealVsEstimada'] as num?)?.toDouble(),
      presupuestado: presupuestado,
      ejecutado: ejecutado,
      desviacionMonto:
          (j['desviacionMonto'] as num?)?.toDouble() ??
          ejecutado - presupuestado,
      umbralPct: (j['umbralPct'] as num?)?.toDouble(),
      superaUmbral: j['superaUmbral'] as bool? ?? false,
      materiales: [
        for (final m in (j['materiales'] as List<dynamic>? ?? const []))
          DesviacionMaterial.desdeJson(m as Map<String, dynamic>),
      ],
    );
  }
}

/// Una fila de la desviación: lo presupuestado y lo ejecutado de un material,
/// y su merma estimada (catálogo) contra la real (kardex).
class DesviacionMaterial {
  const DesviacionMaterial({
    required this.materialId,
    required this.sku,
    required this.nombre,
    required this.unidad,
    required this.cantidadPresupuestada,
    required this.cantidadEjecutada,
    required this.montoPresupuestado,
    required this.montoEjecutado,
    required this.desviacionMonto,
    required this.desviacionPct,
    required this.superaUmbral,
    required this.mermaEstimadaPct,
    required this.mermaRealPct,
  });

  final int materialId;
  final String sku;
  final String nombre;

  /// El catálogo no guarda unidad de medida: hoy llega siempre en `null`.
  final String? unidad;
  final double cantidadPresupuestada;
  final double cantidadEjecutada;
  final double montoPresupuestado;
  final double montoEjecutado;
  final double desviacionMonto;

  /// `null` cuando el material se consumió sin estar presupuestado.
  final double? desviacionPct;
  final bool superaUmbral;

  /// `null` si el material no tiene parámetro de merma.
  final double? mermaEstimadaPct;

  /// `null` si el material no tiene cubicación contra qué medirla.
  final double? mermaRealPct;

  bool get sinPresupuesto => desviacionPct == null;

  /// Plata gastada en algo que no estaba en el presupuesto. El servidor no lo
  /// marca como "supera el umbral" (no hay porcentaje), pero es lo primero que
  /// el jefe de terreno quiere ver.
  bool get consumidoSinPresupuestar =>
      sinPresupuesto && montoPresupuestado == 0 && montoEjecutado > 0;

  factory DesviacionMaterial.desdeJson(Map<String, dynamic> j) =>
      DesviacionMaterial(
        materialId: j['materialId'] as int,
        sku: j['sku'] as String,
        nombre: j['nombre'] as String,
        unidad: j['unidad'] as String?,
        cantidadPresupuestada: (j['cantidadPresupuestada'] as num).toDouble(),
        cantidadEjecutada: (j['cantidadEjecutada'] as num).toDouble(),
        montoPresupuestado: (j['montoPresupuestado'] as num).toDouble(),
        montoEjecutado: (j['montoEjecutado'] as num).toDouble(),
        desviacionMonto: (j['desviacionMonto'] as num).toDouble(),
        desviacionPct: (j['desviacionPct'] as num?)?.toDouble(),
        superaUmbral: j['superaUmbral'] as bool? ?? false,
        mermaEstimadaPct: (j['mermaEstimadaPct'] as num?)?.toDouble(),
        mermaRealPct: (j['mermaRealPct'] as num?)?.toDouble(),
      );
}
