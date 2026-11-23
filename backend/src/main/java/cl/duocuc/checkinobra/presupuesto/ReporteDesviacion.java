package cl.duocuc.checkinobra.presupuesto;

import java.util.List;

/**
 * ReporteDesviacion «value object» del diagrama — no es una entidad
 * persistida, es el resultado que produce ComparadorPresupuesto.
 *
 * <p>Los cuatro primeros campos son el contrato original y no cambian; el resto es el desglose
 * (D8/D9): el desvío en plata, el umbral con que se compara y el detalle por material.
 *
 * <p>{@code desviacionPct} es 0 cuando el presupuesto es 0 (no hay contra qué comparar).
 * {@code superaUmbral} solo marca sobrecostos: {@code desviacionPct > umbralPct}.
 */
public record ReporteDesviacion(
        double desviacionPct,
        double mermaRealVsEstimada,
        double presupuestado,
        double ejecutado,
        double desviacionMonto,
        double umbralPct,
        boolean superaUmbral,
        List<DesviacionMaterial> materiales
) {
}
