package cl.duocuc.checkinobra.metricas;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * Lo que ve bodega de una obra (#203). {@code movimientos} cuenta CANTIDAD DE MOVIMIENTOS por tipo (no
 * unidades), sin huecos: los días (o semanas) sin nada vienen en 0. La {@code fecha} es el día, o el
 * lunes de la semana si la granularidad es {@code SEMANA}.
 *
 * <p>Las herramientas son de la EMPRESA (no tienen obra): {@code herramientasPorEstado} trae todos los
 * estados, aunque sea en 0, y {@code prestadasEnEstaObra} son los préstamos abiertos de esta obra.
 */
public record MetricasBodegaResponse(
        String periodo,
        LocalDate desde,
        LocalDate hasta,
        String granularidad,
        List<MovimientosDelPeriodo> movimientos,
        List<MaterialDespachado> masDespachados,
        Map<String, Long> herramientasPorEstado,
        long totalHerramientas,
        long prestadasEnEstaObra) {

    public record MovimientosDelPeriodo(LocalDate fecha, long recepcion, long despacho, long consumo) {
    }

    /** {@code cantidad} son unidades despachadas en el periodo. */
    public record MaterialDespachado(Long materialId, String sku, String nombre, double cantidad) {
    }
}
