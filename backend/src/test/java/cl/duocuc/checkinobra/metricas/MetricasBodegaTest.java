package cl.duocuc.checkinobra.metricas;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.inventario.EstadoHerramienta;
import cl.duocuc.checkinobra.inventario.TipoMovimiento;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;

import java.net.http.HttpResponse;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * #203 — GET /api/obras/{id}/metricas/bodega: cuántos movimientos hubo por tipo (CANTIDAD de
 * movimientos, no unidades) sin huecos, lo más despachado, y las herramientas de la empresa.
 */
class MetricasBodegaTest extends MetricasBase {

    private String ruta(String periodo) {
        return "/api/obras/" + obra.getId() + "/metricas/bodega" + (periodo == null ? "" : "?periodo=" + periodo);
    }

    private static JsonNode fila(JsonNode movimientos, LocalDate dia) {
        for (JsonNode f : movimientos) {
            if (LocalDate.parse(f.get("fecha").asString()).equals(dia)) {
                return f;
            }
        }
        throw new AssertionError("No hay fila del " + dia);
    }

    // ---- movimientos -----------------------------------------------------

    @Test
    void cuentaMovimientosPorTipoYNoUnidades() throws Exception {
        movimiento(obra, volcanita, TipoMovimiento.RECEPCION, 500, hoy);
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 30, hoy);
        movimiento(obra, tornillo, TipoMovimiento.DESPACHO, 900, hoy);
        movimiento(obra, tornillo, TipoMovimiento.CONSUMO, 7, hoy);
        movimiento(obra, yeso, TipoMovimiento.DESPACHO, 1, hoy.minusDays(2));

        JsonNode j = ok(ruta("7d"), tokenBodeguero);

        assertThat(j.get("granularidad").asString()).isEqualTo("DIA");
        JsonNode deHoy = fila(j.get("movimientos"), hoy);
        assertThat(deHoy.get("recepcion").asInt()).isEqualTo(1);
        assertThat(deHoy.get("despacho").asInt()).isEqualTo(2);
        assertThat(deHoy.get("consumo").asInt()).isEqualTo(1);
        assertThat(fila(j.get("movimientos"), hoy.minusDays(2)).get("despacho").asInt()).isEqualTo(1);
    }

    @Test
    void noTieneHuecos_LosDiasSinNadaVienenEnCero() throws Exception {
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 1, hoy);

        JsonNode movimientos = ok(ruta("7d"), tokenBodeguero).get("movimientos");

        assertThat(movimientos).hasSize(7);
        for (int i = 0; i < 7; i++) {
            assertThat(LocalDate.parse(movimientos.get(i).get("fecha").asString())).isEqualTo(hoy.minusDays(6 - i));
        }
        JsonNode sinNada = fila(movimientos, hoy.minusDays(3));
        assertThat(sinNada.get("recepcion").asInt()).isZero();
        assertThat(sinNada.get("despacho").asInt()).isZero();
        assertThat(sinNada.get("consumo").asInt()).isZero();
    }

    @Test
    void elContratoNoTieneDevolucion() throws Exception {
        JsonNode primera = ok(ruta("7d"), tokenBodeguero).get("movimientos").get(0);

        assertThat(primera.has("devolucion")).isFalse();
        assertThat(primera.propertyNames()).containsExactlyInAnyOrder("fecha", "recepcion", "despacho", "consumo");
    }

    @Test
    void sinPeriodoEsDe30DiasPorDia() throws Exception {
        JsonNode j = ok(ruta(null), tokenBodeguero);

        assertThat(j.get("periodo").asString()).isEqualTo("30d");
        assertThat(j.get("granularidad").asString()).isEqualTo("DIA");
        assertThat(j.get("movimientos")).hasSize(30);
    }

    @Test
    void siElPeriodoPasaDe31DiasLaGranularidadEsPorSemana() throws Exception {
        movimiento(obra, volcanita, TipoMovimiento.RECEPCION, 10, hoy.minusDays(40));
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 1, hoy.minusDays(40));
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 1, hoy);

        JsonNode j = ok(ruta("obra"), tokenBodeguero);

        assertThat(j.get("granularidad").asString()).isEqualTo("SEMANA");
        JsonNode movimientos = j.get("movimientos");
        LocalDate primera = lunes(hoy.minusDays(40));
        assertThat(LocalDate.parse(movimientos.get(0).get("fecha").asString())).isEqualTo(primera);
        assertThat(movimientos).hasSize((int) (lunes(hoy).toEpochDay() - primera.toEpochDay()) / 7 + 1);
        assertThat(movimientos.get(0).get("recepcion").asInt()).isEqualTo(1);
        assertThat(movimientos.get(0).get("despacho").asInt()).isEqualTo(1);
        assertThat(movimientos.get(movimientos.size() - 1).get("despacho").asInt()).isEqualTo(1);
    }

    @Test
    void justoEn31DiasSigueSiendoPorDiaYEn32PasaASemana() throws Exception {
        movimiento(obra, volcanita, TipoMovimiento.RECEPCION, 10, hoy.minusDays(30)); // 31 días contando hoy

        assertThat(ok(ruta("obra"), tokenBodeguero).get("granularidad").asString()).isEqualTo("DIA");

        movimiento(obra, volcanita, TipoMovimiento.RECEPCION, 10, hoy.minusDays(31)); // 32 días

        assertThat(ok(ruta("obra"), tokenBodeguero).get("granularidad").asString()).isEqualTo("SEMANA");
    }

    @Test
    void losMovimientosDeOtraObraNoCuentan() throws Exception {
        Obra otra = obra("Otra obra " + s, empresa, jefe, EstadoObra.ACTIVA);
        movimiento(otra, volcanita, TipoMovimiento.DESPACHO, 5, hoy);

        JsonNode movimientos = ok(ruta("7d"), tokenBodeguero).get("movimientos");

        assertThat(fila(movimientos, hoy).get("despacho").asInt()).isZero();
    }

    // ---- más despachados -------------------------------------------------

    @Test
    void masDespachadosSonLosCuatroDeMasUnidadesDespachadasEnElPeriodo() throws Exception {
        for (int i = 1; i <= 5; i++) {
            Material m = material("MAT" + i + "-" + s, 10, empresa);
            movimiento(obra, m, TipoMovimiento.DESPACHO, i * 10, hoy);
        }
        // Un consumo, una recepción y un despacho fuera del periodo no cuentan.
        movimiento(obra, volcanita, TipoMovimiento.CONSUMO, 9999, hoy);
        movimiento(obra, volcanita, TipoMovimiento.RECEPCION, 9999, hoy);
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 9999, hoy.minusDays(20));

        JsonNode top = ok(ruta("7d"), tokenBodeguero).get("masDespachados");

        assertThat(top).hasSize(4);
        assertThat(top.get(0).get("cantidad").asDouble()).isEqualTo(50);
        assertThat(top.get(1).get("cantidad").asDouble()).isEqualTo(40);
        assertThat(top.get(2).get("cantidad").asDouble()).isEqualTo(30);
        assertThat(top.get(3).get("cantidad").asDouble()).isEqualTo(20);
        assertThat(top.get(0).get("sku").asString()).startsWith("MAT5-");
        assertThat(top.get(0).get("nombre").asString()).isNotBlank();
        assertThat(top.get(0).get("materialId").asLong()).isPositive();
    }

    @Test
    void sumaLosDespachosDelMismoMaterial() throws Exception {
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 3, hoy);
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 4.5, hoy.minusDays(1));

        JsonNode top = ok(ruta("7d"), tokenBodeguero).get("masDespachados");

        assertThat(top).hasSize(1);
        assertThat(top.get(0).get("cantidad").asDouble()).isEqualTo(7.5);
    }

    // ---- herramientas ----------------------------------------------------

    @Test
    void lasHerramientasSonDeLaEmpresaPorEstadoConTodosLosEstadosDelEnum() throws Exception {
        herramienta("Taladro", EstadoHerramienta.DISPONIBLE, empresa);
        herramienta("Sierra", EstadoHerramienta.DISPONIBLE, empresa);
        herramienta("Nivel", EstadoHerramienta.PRESTADA, empresa);
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        herramienta("Ajena", EstadoHerramienta.MANTENCION, otra);

        JsonNode j = ok(ruta("7d"), tokenBodeguero);

        JsonNode porEstado = j.get("herramientasPorEstado");
        for (EstadoHerramienta e : EstadoHerramienta.values()) {
            assertThat(porEstado.has(e.name())).as(e.name()).isTrue();
        }
        assertThat(porEstado.get("DISPONIBLE").asInt()).isEqualTo(2);
        assertThat(porEstado.get("PRESTADA").asInt()).isEqualTo(1);
        assertThat(porEstado.get("MANTENCION").asInt()).as("la de otra empresa no cuenta").isZero();
        assertThat(j.get("totalHerramientas").asInt()).isEqualTo(3);
    }

    @Test
    void prestadasEnEstaObraSonLosPrestamosAbiertosDeEsaObra() throws Exception {
        Obra otra = obra("Otra obra " + s, empresa, jefe, EstadoObra.ACTIVA);
        prestamo(herramienta("A", EstadoHerramienta.PRESTADA, empresa), obra, false);
        prestamo(herramienta("B", EstadoHerramienta.PRESTADA, empresa), obra, false);
        prestamo(herramienta("C", EstadoHerramienta.DISPONIBLE, empresa), obra, true);   // ya devuelta
        prestamo(herramienta("D", EstadoHerramienta.PRESTADA, empresa), otra, false);    // en otra obra

        JsonNode j = ok(ruta("7d"), tokenBodeguero);

        assertThat(j.get("prestadasEnEstaObra").asInt()).isEqualTo(2);
        assertThat(j.get("herramientasPorEstado").get("PRESTADA").asInt()).isEqualTo(3);
        assertThat(j.get("totalHerramientas").asInt()).isEqualTo(4);
    }

    @Test
    void sinHerramientasTodoVieneEnCero() throws Exception {
        JsonNode j = ok(ruta("7d"), tokenBodeguero);

        assertThat(j.get("totalHerramientas").asInt()).isZero();
        assertThat(j.get("prestadasEnEstaObra").asInt()).isZero();
        assertThat(j.get("herramientasPorEstado").get("DISPONIBLE").asInt()).isZero();
        assertThat(j.get("masDespachados")).isEmpty();
    }

    // ---- acceso ----------------------------------------------------------

    @Test
    void bodegueroJefeYAdminEntran_ElTrabajadorNo() throws Exception {
        assertThat(get(ruta(null), tokenBodeguero).statusCode()).isEqualTo(200);
        assertThat(get(ruta(null), tokenJefe).statusCode()).isEqualTo(200);
        assertThat(get(ruta(null), tokenAdmin).statusCode()).isEqualTo(200);
        assertThat(get(ruta(null), tokenTrabajador).statusCode()).isEqualTo(403);
        assertThat(get(ruta(null), null).statusCode()).isIn(401, 403);
    }

    @Test
    void laObraDeOtraEmpresaEs404() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        String tokenAjeno = token(usuario("bodega-b", RolUsuario.BODEGUERO, otra));

        assertThat(get(ruta(null), tokenAjeno).statusCode()).isEqualTo(404);
        assertThat(get("/api/obras/999999999/metricas/bodega", tokenAjeno).statusCode()).isEqualTo(404);
    }

    @Test
    void unPeriodoQueNoExisteEs400() throws Exception {
        HttpResponse<String> r = get(ruta("1y"), tokenBodeguero);

        assertThat(r.statusCode()).isEqualTo(400);
    }

    private static LocalDate lunes(LocalDate dia) {
        return dia.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
    }
}
