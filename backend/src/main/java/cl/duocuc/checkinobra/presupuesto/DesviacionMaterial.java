package cl.duocuc.checkinobra.presupuesto;

/**
 * Una fila del desglose de la desviación: un material, lo presupuestado contra lo ejecutado.
 *
 * <p>{@code unidad} viene siempre nula: el catálogo de materiales no guarda unidad de medida.
 * {@code desviacionPct} es nulo cuando el material no estaba en el presupuesto (no hay base contra
 * qué medir); aun así aparece, con presupuestado 0. {@code mermaEstimadaPct} es la merma
 * parametrizada del catálogo y {@code mermaRealPct} es lo ejecutado contra lo neto cubicado;
 * cada una es nula si no hay parámetro o cubicación de donde sacarla.
 */
public record DesviacionMaterial(
        Long materialId,
        String sku,
        String nombre,
        String unidad,
        double cantidadPresupuestada,
        double cantidadEjecutada,
        double montoPresupuestado,
        double montoEjecutado,
        double desviacionMonto,
        Double desviacionPct,
        boolean superaUmbral,
        Double mermaEstimadaPct,
        Double mermaRealPct
) {
}
