package cl.duocuc.checkinobra.metricas;

import java.time.LocalDate;
import java.util.List;

/**
 * Lo que ve el jefe de terreno de su obra (#203). Solo escalares: el ejecutado se valora como en
 * {@code ComparadorPresupuestoService} (despacho + consumo del kardex, al precio con que se presupuestó).
 *
 * <p>{@code porMaterial} son los 5 materiales con más ejecutado y {@code otros} el resto; ambos son
 * acumulados de toda la obra hasta {@code hasta} (el presupuesto no tiene periodo), y solo cuentan
 * materiales con ejecutado. Es dato real del kardex: no se atribuye consumo a partidas porque el kardex
 * no sabe de partidas.
 */
public record MetricasJefeResponse(
        String periodo,
        LocalDate desde,
        LocalDate hasta,
        GastoAcumulado gastoAcumulado,
        List<MaterialEjecutado> porMaterial,
        Otros otros,
        double umbralPct) {

    /** {@code ejecutadoTotal} es el acumulado de toda la obra hasta {@code hasta}. */
    public record GastoAcumulado(double presupuestoTotal, double ejecutadoTotal, List<PuntoSemanal> serie) {
    }

    /** Ejecutado acumulado desde el inicio de la obra hasta el cierre de la semana (o hasta hoy). */
    public record PuntoSemanal(String etiqueta, LocalDate desde, double ejecutadoAcumulado) {
    }

    /** {@code desviacionPct} es nulo si el material no estaba en el presupuesto. */
    public record MaterialEjecutado(
            Long materialId,
            String sku,
            String nombre,
            double presupuestado,
            double ejecutado,
            Double desviacionPct,
            boolean superaUmbral) {
    }

    /** Los materiales que no entraron al top: cuántos son y cuánto suman. */
    public record Otros(int cantidad, double ejecutado) {
    }
}
