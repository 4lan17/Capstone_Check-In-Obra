package cl.duocuc.checkinobra.presupuesto;

/**
 * ReporteDesviacion «value object» del diagrama — no es una entidad
 * persistida, es el resultado que produce ComparadorPresupuesto.
 */
public record ReporteDesviacion(
        double desviacionPct,
        double mermaRealVsEstimada,
        double presupuestado,
        double ejecutado
) {
}
