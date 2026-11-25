package cl.duocuc.checkinobra.metricas;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * Lo que ve el administrador de toda la empresa (#203).
 *
 * <p>{@code resueltas} es por COHORTE: de las alertas generadas esa semana, cuántas están resueltas
 * hoy. La alerta no guarda cuándo se resolvió, así que no hay "resueltas esa semana".
 * {@code desviacionPorObra} son las obras ACTIVAS, con la desviación acumulada contra su presupuesto
 * (nula si no tiene presupuesto). {@code umbralPct} es el de {@code checkinobra.presupuesto.umbral-desviacion-pct}.
 */
public record MetricasEmpresaResponse(
        String periodo,
        LocalDate desde,
        LocalDate hasta,
        List<AlertasDeLaSemana> alertasPorSemana,
        List<DesviacionDeObra> desviacionPorObra,
        double umbralPct,
        Map<String, Long> usuariosPorRol,
        Map<String, Long> obrasPorEstado) {

    public record AlertasDeLaSemana(String etiqueta, LocalDate desde, long generadas, long resueltas) {
    }

    public record DesviacionDeObra(Long obraId, String nombre, Double desviacionPct) {
    }
}
