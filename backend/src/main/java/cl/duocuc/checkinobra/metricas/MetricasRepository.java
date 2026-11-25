package cl.duocuc.checkinobra.metricas;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.Date;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Las consultas de las métricas (#203). Todas agregan en la base —una consulta por métrica, sin recorrer
 * entidades— y todas son de solo lectura. Las fechas del kardex y de las alertas son hora de Chile sin
 * zona, igual que el servidor (compose fija {@code TZ=America/Santiago}).
 *
 * <p><b>Cómo se valora el ejecutado:</b> como {@code ComparadorPresupuestoService}. Despacho + consumo
 * del kardex, al precio con que se presupuestó el material en esa obra (el promedio ponderado de sus
 * ítems, porque el precio se copia al agregar el ítem y no sigue al catálogo); un material consumido
 * sin estar presupuestado usa el precio vigente del catálogo.
 *
 * <p>Todas filtran por la obra o por la empresa que ya validó el servicio: en una base compartida (las
 * pruebas) nunca se mezclan empresas.
 */
@Repository
class MetricasRepository {

    /** Valor de una unidad de un material en la obra: el precio congelado del presupuesto o, si no está, el del catálogo. */
    private static final String PRECIO_DE_VALORACION =
            "CASE WHEN pres.cantidad > 0 THEN pres.monto / pres.cantidad ELSE m.precio_unitario END";

    /** Lo presupuestado por material en una obra: cantidad y monto de todos sus ítems. */
    private static final String PRESUPUESTADO_POR_MATERIAL = """
            SELECT pi.material_id, SUM(pi.cantidad) AS cantidad, SUM(pi.subtotal) AS monto
              FROM presupuesto_items pi
              JOIN presupuestos p ON p.id = pi.presupuesto_id
             WHERE p.obra_id = :obraId
             GROUP BY pi.material_id""";

    private static final String ES_EJECUTADO = "k.tipo_movimiento IN ('DESPACHO', 'CONSUMO')";

    private final NamedParameterJdbcTemplate jdbc;

    MetricasRepository(JdbcTemplate jdbc) {
        this.jdbc = new NamedParameterJdbcTemplate(jdbc);
    }

    record GastoDeLaSemana(LocalDate semana, double monto) {
    }

    record EjecutadoDeMaterial(Long materialId, String sku, String nombre, double presupuestado, double ejecutado) {
    }

    record AlertasDeLaSemana(LocalDate semana, long generadas, long resueltas) {
    }

    record ObraConPresupuesto(Long obraId, String nombre, double presupuestado, double ejecutado) {
    }

    // ---- obra ------------------------------------------------------------

    Optional<LocalDate> primerMovimiento(Long obraId) {
        List<LocalDate> fechas = jdbc.query(
                "SELECT CAST(MIN(fecha) AS date) AS primera FROM kardex_movimientos WHERE obra_id = :obraId",
                new MapSqlParameterSource("obraId", obraId),
                (rs, i) -> rs.getDate("primera") == null ? null : rs.getDate("primera").toLocalDate());
        return fechas.stream().filter(f -> f != null).findFirst();
    }

    double presupuestoTotal(Long obraId) {
        return jdbc.query("SELECT total FROM presupuestos WHERE obra_id = :obraId",
                new MapSqlParameterSource("obraId", obraId), (rs, i) -> rs.getDouble("total"))
                .stream().findFirst().orElse(0.0);
    }

    /** El ejecutado de cada semana ISO con movimientos, valorado, hasta el instante (exclusivo). */
    List<GastoDeLaSemana> gastoPorSemana(Long obraId, LocalDateTime hastaExclusivo) {
        return jdbc.query("""
                WITH pres AS (%s)
                SELECT CAST(date_trunc('week', k.fecha) AS date) AS semana,
                       SUM(k.cantidad * %s) AS monto
                  FROM kardex_movimientos k
                  JOIN materiales m ON m.id = k.material_id
                  LEFT JOIN pres ON pres.material_id = k.material_id
                 WHERE k.obra_id = :obraId AND %s AND k.fecha < :hastaExclusivo
                 GROUP BY 1
                 ORDER BY 1""".formatted(PRESUPUESTADO_POR_MATERIAL, PRECIO_DE_VALORACION, ES_EJECUTADO),
                new MapSqlParameterSource("obraId", obraId).addValue("hastaExclusivo", hastaExclusivo),
                (rs, i) -> new GastoDeLaSemana(rs.getDate("semana").toLocalDate(), rs.getDouble("monto")));
    }

    /** Los materiales con ejecutado en la obra, con lo que se presupuestó de cada uno. */
    List<EjecutadoDeMaterial> ejecutadoPorMaterial(Long obraId, LocalDateTime hastaExclusivo) {
        return jdbc.query("""
                WITH pres AS (%s),
                     ejec AS (SELECT k.material_id, SUM(k.cantidad) AS cantidad
                                FROM kardex_movimientos k
                               WHERE k.obra_id = :obraId AND %s AND k.fecha < :hastaExclusivo
                               GROUP BY k.material_id)
                SELECT m.id, m.sku, m.nombre,
                       COALESCE(pres.monto, 0) AS presupuestado,
                       ejec.cantidad * %s AS ejecutado
                  FROM ejec
                  JOIN materiales m ON m.id = ejec.material_id
                  LEFT JOIN pres ON pres.material_id = ejec.material_id"""
                        .formatted(PRESUPUESTADO_POR_MATERIAL, ES_EJECUTADO, PRECIO_DE_VALORACION),
                new MapSqlParameterSource("obraId", obraId).addValue("hastaExclusivo", hastaExclusivo),
                (rs, i) -> new EjecutadoDeMaterial(rs.getLong("id"), rs.getString("sku"), rs.getString("nombre"),
                        rs.getDouble("presupuestado"), rs.getDouble("ejecutado")));
    }

    /**
     * Cantidad de movimientos por tipo en cada día —o en cada semana ISO— del periodo, con todos los
     * días (o semanas) aunque no tengan ninguno.
     */
    List<MetricasBodegaResponse.MovimientosDelPeriodo> movimientos(Long obraId, PeriodoMetricas periodo) {
        boolean porSemana = periodo.porSemana();
        LocalDate inicio = porSemana ? PeriodoMetricas.lunesDe(periodo.desde()) : periodo.desde();
        LocalDate fin = porSemana ? PeriodoMetricas.lunesDe(periodo.hasta()) : periodo.hasta();
        // Primero se cuenta (una sola pasada por los movimientos de la obra en el rango) y después se
        // une a la serie de días o semanas, para que los vacíos salgan en 0. Unir antes obligaría a
        // recorrer los movimientos de la obra una vez por cada día.
        return jdbc.query("""
                WITH conteo AS (
                    SELECT date_trunc(:unidad, k.fecha) AS d,
                           COUNT(*) FILTER (WHERE k.tipo_movimiento = 'RECEPCION') AS recepcion,
                           COUNT(*) FILTER (WHERE k.tipo_movimiento = 'DESPACHO') AS despacho,
                           COUNT(*) FILTER (WHERE k.tipo_movimiento = 'CONSUMO') AS consumo
                      FROM kardex_movimientos k
                     WHERE k.obra_id = :obraId AND k.fecha >= :inicio AND k.fecha < :hastaExclusivo
                     GROUP BY 1)
                SELECT CAST(g.d AS date) AS fecha,
                       COALESCE(c.recepcion, 0) AS recepcion,
                       COALESCE(c.despacho, 0) AS despacho,
                       COALESCE(c.consumo, 0) AS consumo
                  FROM generate_series(CAST(:inicio AS timestamp), CAST(:fin AS timestamp), CAST(:paso AS interval)) AS g(d)
                  LEFT JOIN conteo c ON c.d = g.d
                 ORDER BY g.d""",
                new MapSqlParameterSource("obraId", obraId)
                        .addValue("inicio", inicio.atStartOfDay()).addValue("fin", fin.atStartOfDay())
                        .addValue("hastaExclusivo", periodo.hasta().plusDays(1).atStartOfDay())
                        .addValue("unidad", porSemana ? "week" : "day")
                        .addValue("paso", porSemana ? "7 days" : "1 day"),
                (rs, i) -> new MetricasBodegaResponse.MovimientosDelPeriodo(
                        rs.getDate("fecha").toLocalDate(),
                        rs.getLong("recepcion"), rs.getLong("despacho"), rs.getLong("consumo")));
    }

    /** Los materiales con más unidades despachadas en el periodo (solo DESPACHO). */
    List<MetricasBodegaResponse.MaterialDespachado> masDespachados(Long obraId, PeriodoMetricas periodo, int limite) {
        return jdbc.query("""
                SELECT m.id, m.sku, m.nombre, SUM(k.cantidad) AS cantidad
                  FROM kardex_movimientos k
                  JOIN materiales m ON m.id = k.material_id
                 WHERE k.obra_id = :obraId AND k.tipo_movimiento = 'DESPACHO'
                   AND k.fecha >= :desde AND k.fecha < :hastaExclusivo
                 GROUP BY m.id, m.sku, m.nombre
                 ORDER BY cantidad DESC, m.nombre
                 LIMIT :limite""",
                new MapSqlParameterSource("obraId", obraId)
                        .addValue("desde", periodo.desde().atStartOfDay())
                        .addValue("hastaExclusivo", periodo.hasta().plusDays(1).atStartOfDay())
                        .addValue("limite", limite),
                (rs, i) -> new MetricasBodegaResponse.MaterialDespachado(
                        rs.getLong("id"), rs.getString("sku"), rs.getString("nombre"), rs.getDouble("cantidad")));
    }

    long prestamosAbiertos(Long obraId) {
        Long n = jdbc.queryForObject(
                "SELECT COUNT(*) FROM prestamos_herramienta WHERE obra_id = :obraId AND fecha_devol_real IS NULL",
                new MapSqlParameterSource("obraId", obraId), Long.class);
        return n == null ? 0 : n;
    }

    // ---- empresa ---------------------------------------------------------

    Map<String, Long> herramientasPorEstado(Long empresaId) {
        return contar("SELECT estado AS clave, COUNT(*) AS n FROM herramientas WHERE empresa_id = :empresaId GROUP BY estado",
                empresaId);
    }

    Map<String, Long> usuariosPorRol(Long empresaId) {
        return contar("SELECT rol AS clave, COUNT(*) AS n FROM usuarios WHERE empresa_id = :empresaId GROUP BY rol",
                empresaId);
    }

    Map<String, Long> obrasPorEstado(Long empresaId) {
        return contar("SELECT estado AS clave, COUNT(*) AS n FROM obras WHERE empresa_id = :empresaId GROUP BY estado",
                empresaId);
    }

    private Map<String, Long> contar(String sql, Long empresaId) {
        Map<String, Long> conteo = new LinkedHashMap<>();
        jdbc.query(sql, new MapSqlParameterSource("empresaId", empresaId),
                rs -> {
                    conteo.put(rs.getString("clave"), rs.getLong("n"));
                });
        return conteo;
    }

    Optional<LocalDate> primeraAlerta(Long empresaId) {
        List<Date> fechas = jdbc.query("""
                SELECT CAST(MIN(a.fecha) AS date) AS primera
                  FROM alertas a JOIN obras o ON o.id = a.obra_id
                 WHERE o.empresa_id = :empresaId""",
                new MapSqlParameterSource("empresaId", empresaId), (rs, i) -> rs.getDate("primera"));
        return fechas.stream().filter(f -> f != null).map(Date::toLocalDate).findFirst();
    }

    /**
     * Las alertas generadas en cada semana ISO con alguna, y de ellas cuántas están resueltas hoy: es
     * por cohorte, porque la alerta no guarda cuándo se resolvió.
     */
    List<AlertasDeLaSemana> alertasPorSemana(Long empresaId, LocalDateTime desde, LocalDateTime hastaExclusivo) {
        return jdbc.query("""
                SELECT CAST(date_trunc('week', a.fecha) AS date) AS semana,
                       COUNT(*) AS generadas,
                       COUNT(*) FILTER (WHERE a.resuelto) AS resueltas
                  FROM alertas a JOIN obras o ON o.id = a.obra_id
                 WHERE o.empresa_id = :empresaId AND a.fecha >= :desde AND a.fecha < :hastaExclusivo
                 GROUP BY 1
                 ORDER BY 1""",
                new MapSqlParameterSource("empresaId", empresaId)
                        .addValue("desde", desde).addValue("hastaExclusivo", hastaExclusivo),
                (rs, i) -> new AlertasDeLaSemana(rs.getDate("semana").toLocalDate(),
                        rs.getLong("generadas"), rs.getLong("resueltas")));
    }

    /** Presupuestado y ejecutado de cada obra ACTIVA de la empresa, en una sola consulta. */
    List<ObraConPresupuesto> presupuestoYEjecutadoDeObrasActivas(Long empresaId) {
        return jdbc.query("""
                WITH activas AS (SELECT id, nombre FROM obras WHERE empresa_id = :empresaId AND estado = 'ACTIVA'),
                     pres AS (SELECT p.obra_id, pi.material_id, SUM(pi.cantidad) AS cantidad, SUM(pi.subtotal) AS monto
                                FROM presupuesto_items pi
                                JOIN presupuestos p ON p.id = pi.presupuesto_id
                               WHERE p.obra_id IN (SELECT id FROM activas)
                               GROUP BY p.obra_id, pi.material_id),
                     ejec AS (SELECT k.obra_id, SUM(k.cantidad * %s) AS monto
                                FROM kardex_movimientos k
                                JOIN materiales m ON m.id = k.material_id
                                LEFT JOIN pres ON pres.obra_id = k.obra_id AND pres.material_id = k.material_id
                               WHERE k.obra_id IN (SELECT id FROM activas) AND %s
                               GROUP BY k.obra_id)
                SELECT a.id, a.nombre, COALESCE(p.total, 0) AS presupuestado, COALESCE(ejec.monto, 0) AS ejecutado
                  FROM activas a
                  LEFT JOIN presupuestos p ON p.obra_id = a.id
                  LEFT JOIN ejec ON ejec.obra_id = a.id
                 ORDER BY a.nombre, a.id""".formatted(PRECIO_DE_VALORACION, ES_EJECUTADO),
                new MapSqlParameterSource("empresaId", empresaId),
                (rs, i) -> new ObraConPresupuesto(rs.getLong("id"), rs.getString("nombre"),
                        rs.getDouble("presupuestado"), rs.getDouble("ejecutado")));
    }
}
