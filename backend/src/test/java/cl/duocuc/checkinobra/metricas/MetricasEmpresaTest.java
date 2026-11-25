package cl.duocuc.checkinobra.metricas;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.inventario.TipoMovimiento;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/**
 * #203 — GET /api/metricas/empresa (solo ADMIN): alertas por semana (por cohorte), desviación de cada
 * obra activa, y cuántos usuarios y obras hay.
 */
class MetricasEmpresaTest extends MetricasBase {

    private static final String RUTA = "/api/metricas/empresa";

    // ---- alertas por semana ----------------------------------------------

    @Test
    void lasAlertasSeCuentanPorSemanaDeGeneracionYLasResueltasSonLasDeEsaCohorte() throws Exception {
        LocalDate lunesDeEstaSemana = lunes(hoy);
        LocalDate haceDosSemanas = lunesDeEstaSemana.minusWeeks(2).plusDays(1);
        alerta(obra, haceDosSemanas, true);
        alerta(obra, haceDosSemanas, true);
        alerta(obra, haceDosSemanas, false);
        alerta(obra, lunesDeEstaSemana, false);

        JsonNode semanas = ok(RUTA + "?periodo=30d", tokenAdmin).get("alertasPorSemana");

        JsonNode antes = semana(semanas, lunesDeEstaSemana.minusWeeks(2));
        assertThat(antes.get("generadas").asInt()).isEqualTo(3);
        assertThat(antes.get("resueltas").asInt()).isEqualTo(2);
        JsonNode esta = semana(semanas, lunesDeEstaSemana);
        assertThat(esta.get("generadas").asInt()).isEqualTo(1);
        assertThat(esta.get("resueltas").asInt()).isZero();
    }

    @Test
    void lasSemanasSinAlertasVienenEnCeroYEtiquetadasDesdeS1() throws Exception {
        JsonNode j = ok(RUTA + "?periodo=30d", tokenAdmin);
        JsonNode semanas = j.get("alertasPorSemana");

        LocalDate primera = lunes(hoy.minusDays(29));
        int cantidad = (int) (lunes(hoy).toEpochDay() - primera.toEpochDay()) / 7 + 1;
        assertThat(semanas).hasSize(cantidad);
        for (int i = 0; i < cantidad; i++) {
            assertThat(semanas.get(i).get("etiqueta").asString()).isEqualTo("S" + (i + 1));
            assertThat(LocalDate.parse(semanas.get(i).get("desde").asString())).isEqualTo(primera.plusWeeks(i));
            assertThat(semanas.get(i).get("generadas").asInt()).isZero();
            assertThat(semanas.get(i).get("resueltas").asInt()).isZero();
        }
    }

    @Test
    void lasAlertasFueraDelPeriodoNoCuentan() throws Exception {
        alerta(obra, hoy.minusDays(60), false);

        JsonNode semanas = ok(RUTA + "?periodo=7d", tokenAdmin).get("alertasPorSemana");

        int total = 0;
        for (JsonNode s : semanas) {
            total += s.get("generadas").asInt();
        }
        assertThat(total).isZero();
    }

    @Test
    void sinPeriodoEsDe30Dias_ObraAbarcaTodoElHistorialDeAlertas() throws Exception {
        alerta(obra, hoy.minusDays(60), true);

        assertThat(ok(RUTA, tokenAdmin).get("periodo").asString()).isEqualTo("30d");
        JsonNode j = ok(RUTA + "?periodo=obra", tokenAdmin);
        assertThat(j.get("periodo").asString()).isEqualTo("obra");
        assertThat(LocalDate.parse(j.get("desde").asString())).isEqualTo(hoy.minusDays(60));
        int generadas = 0;
        for (JsonNode s : j.get("alertasPorSemana")) {
            generadas += s.get("generadas").asInt();
        }
        assertThat(generadas).isEqualTo(1);
    }

    @Test
    void laAlertaDeOtraEmpresaNoCuenta() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        Obra deOtra = obra("De otra " + s, otra, null, EstadoObra.ACTIVA);
        alerta(deOtra, hoy, false);

        JsonNode semanas = ok(RUTA + "?periodo=7d", tokenAdmin).get("alertasPorSemana");

        assertThat(semana(semanas, lunes(hoy)).get("generadas").asInt()).isZero();
    }

    // ---- desviación por obra ---------------------------------------------

    @Test
    void desviacionPorObraSoloDeLasActivasConSuPorcentaje() throws Exception {
        presupuesto(obra, volcanita, 10.0);                       // 50.000
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 12, hoy); // 60.000 → +20 %
        Obra cerrada = obra("Cerrada " + s, empresa, jefe, EstadoObra.CERRADA);
        presupuesto(cerrada, volcanita, 1.0);

        JsonNode filas = ok(RUTA, tokenAdmin).get("desviacionPorObra");

        assertThat(filas).hasSize(1);
        assertThat(filas.get(0).get("obraId").asLong()).isEqualTo(obra.getId());
        assertThat(filas.get(0).get("nombre").asString()).isEqualTo(obra.getNombre());
        assertThat(filas.get(0).get("desviacionPct").asDouble()).isCloseTo(20, within(0.01));
    }

    @Test
    void unaObraSinPresupuestoTraeDesviacionNulaYNoDa500() throws Exception {
        Obra sinPresupuesto = obra("Sin presupuesto " + s, empresa, jefe, EstadoObra.ACTIVA);
        movimiento(sinPresupuesto, yeso, TipoMovimiento.DESPACHO, 3, hoy);

        JsonNode filas = ok(RUTA, tokenAdmin).get("desviacionPorObra");

        JsonNode fila = null;
        for (JsonNode f : filas) {
            if (f.get("obraId").asLong() == sinPresupuesto.getId()) {
                fila = f;
            }
        }
        assertThat(fila).isNotNull();
        assertThat(fila.get("desviacionPct").isNull()).isTrue();
    }

    @Test
    void unaObraConPresupuestoPeroSinGastoEsMenos100() throws Exception {
        presupuesto(obra, volcanita, 10.0);

        JsonNode filas = ok(RUTA, tokenAdmin).get("desviacionPorObra");

        assertThat(filas.get(0).get("desviacionPct").asDouble()).isCloseTo(-100, within(0.01));
    }

    @Test
    void laDesviacionValoraAlPrecioCongeladoYNoAlDelCatalogo() throws Exception {
        presupuesto(obra, volcanita, 10.0);
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 10, hoy);
        volcanita.setPrecioUnitario(9999);
        materialRepository.save(volcanita);

        JsonNode filas = ok(RUTA, tokenAdmin).get("desviacionPorObra");

        assertThat(filas.get(0).get("desviacionPct").asDouble()).isCloseTo(0, within(0.01));
    }

    @Test
    void lasObrasDeOtraEmpresaNoAparecen() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        obra("De otra " + s, otra, null, EstadoObra.ACTIVA);

        JsonNode filas = ok(RUTA, tokenAdmin).get("desviacionPorObra");

        for (JsonNode f : filas) {
            assertThat(f.get("nombre").asString()).doesNotContain("De otra");
        }
    }

    // ---- umbral y conteos ------------------------------------------------

    @Test
    void trae_elUmbralDeEmpresa_Usuarios_Y_ObrasPorEstado() throws Exception {
        obra("Cerrada " + s, empresa, jefe, EstadoObra.CERRADA);
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        usuario("ajeno", RolUsuario.ADMIN, otra);
        obra("De otra " + s, otra, null, EstadoObra.ACTIVA);

        JsonNode j = ok(RUTA, tokenAdmin);

        assertThat(j.get("umbralPct").asDouble()).isEqualTo(10);
        JsonNode roles = j.get("usuariosPorRol");
        assertThat(roles.get("ADMIN").asInt()).isEqualTo(1);
        assertThat(roles.get("JEFE_TERRENO").asInt()).isEqualTo(1);
        assertThat(roles.get("BODEGUERO").asInt()).isEqualTo(1);
        assertThat(roles.get("TRABAJADOR").asInt()).isEqualTo(1);
        assertThat(roles.has("PLATAFORMA")).as("no es un rol de empresa").isFalse();
        JsonNode estados = j.get("obrasPorEstado");
        assertThat(estados.get("ACTIVA").asInt()).isEqualTo(1);
        assertThat(estados.get("CERRADA").asInt()).isEqualTo(1);
    }

    @Test
    void losRolesSinUsuariosVienenEnCero() throws Exception {
        Empresa chica = empresaRepository.save(Empresa.builder().nombre("Chica " + s).rut("C-" + s).build());
        String tokenChica = token(usuario("admin-c", RolUsuario.ADMIN, chica));

        JsonNode j = ok(RUTA, tokenChica);

        assertThat(j.get("usuariosPorRol").get("ADMIN").asInt()).isEqualTo(1);
        assertThat(j.get("usuariosPorRol").get("TRABAJADOR").asInt()).isZero();
        assertThat(j.get("obrasPorEstado").get("ACTIVA").asInt()).isZero();
        assertThat(j.get("obrasPorEstado").get("CERRADA").asInt()).isZero();
        assertThat(j.get("desviacionPorObra")).isEmpty();
    }

    // ---- acceso ----------------------------------------------------------

    @Test
    void soloElAdminEntra() throws Exception {
        assertThat(get(RUTA, tokenAdmin).statusCode()).isEqualTo(200);
        assertThat(get(RUTA, tokenJefe).statusCode()).isEqualTo(403);
        assertThat(get(RUTA, tokenBodeguero).statusCode()).isEqualTo(403);
        assertThat(get(RUTA, tokenTrabajador).statusCode()).isEqualTo(403);
        assertThat(get(RUTA, null).statusCode()).isIn(401, 403);
    }

    @Test
    void unPeriodoQueNoExisteEs400() throws Exception {
        assertThat(get(RUTA + "?periodo=semana", tokenAdmin).statusCode()).isEqualTo(400);
    }

    // ---------------------------------------------------------------------

    private static JsonNode semana(JsonNode semanas, LocalDate lunes) {
        for (JsonNode s : semanas) {
            if (LocalDate.parse(s.get("desde").asString()).equals(lunes)) {
                return s;
            }
        }
        throw new AssertionError("No hay semana que empiece el " + lunes);
    }

    private static LocalDate lunes(LocalDate dia) {
        return dia.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
    }
}
