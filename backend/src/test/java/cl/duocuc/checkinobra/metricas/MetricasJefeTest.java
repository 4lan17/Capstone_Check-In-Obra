package cl.duocuc.checkinobra.metricas;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.inventario.TipoMovimiento;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;

import java.net.http.HttpResponse;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/**
 * #203 — GET /api/obras/{id}/metricas/jefe: gasto acumulado por semana, ejecutado por material
 * (top 5 y el resto) y la desviación contra el presupuesto, con el umbral.
 *
 * Datos base (precios de catálogo: volcanita 5000, tornillo 10, yeso 300):
 *   presupuesto congelado: volcanita 10,8 u (54.000) + tornillo 100 u (1.000) = 55.000
 *   kardex: volcanita despacho 1 u (hace 45 días), 5 u (hace 20), consumo 4 u (hace 10), despacho 2 u (hoy)
 *           = 12 u = 60.000; yeso despacho 5 u hoy (sin presupuestar) = 1.500; una recepción que no cuenta.
 *   ejecutado total = 61.500
 */
class MetricasJefeTest extends MetricasBase {

    @BeforeEach
    void armarElGasto() {
        presupuesto(obra, volcanita, 10.8, tornillo, 100.0);
        movimiento(obra, volcanita, TipoMovimiento.RECEPCION, 100, hoy.minusDays(50));
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 1, hoy.minusDays(45));
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 5, hoy.minusDays(20));
        movimiento(obra, volcanita, TipoMovimiento.CONSUMO, 4, hoy.minusDays(10));
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 2, hoy);
        movimiento(obra, yeso, TipoMovimiento.RECEPCION, 10, hoy.minusDays(1));
        movimiento(obra, yeso, TipoMovimiento.DESPACHO, 5, hoy);
    }

    private String ruta(String periodo) {
        return "/api/obras/" + obra.getId() + "/metricas/jefe" + (periodo == null ? "" : "?periodo=" + periodo);
    }

    // ---- periodo y gasto acumulado ----------------------------------------

    @Test
    void sinPeriodoEsDe30DiasYTrae_presupuestoYEjecutadoTotal() throws Exception {
        JsonNode j = ok(ruta(null), tokenJefe);

        assertThat(j.get("periodo").asString()).isEqualTo("30d");
        assertThat(LocalDate.parse(j.get("desde").asString())).isEqualTo(hoy.minusDays(29));
        assertThat(LocalDate.parse(j.get("hasta").asString())).isEqualTo(hoy);
        assertThat(j.get("gastoAcumulado").get("presupuestoTotal").asDouble()).isEqualTo(55000);
        assertThat(j.get("gastoAcumulado").get("ejecutadoTotal").asDouble()).isEqualTo(61500);
        assertThat(j.get("umbralPct").asDouble()).isEqualTo(10);
    }

    @Test
    void laSerieTieneUnaSemanaPorCadaSemanaIsoDelPeriodoYEtiquetaDesdeS1() throws Exception {
        JsonNode serie = ok(ruta("30d"), tokenJefe).get("gastoAcumulado").get("serie");

        LocalDate primera = lunes(hoy.minusDays(29));
        int semanas = (int) (lunes(hoy).toEpochDay() - primera.toEpochDay()) / 7 + 1;
        assertThat(serie).hasSize(semanas);
        for (int i = 0; i < semanas; i++) {
            assertThat(serie.get(i).get("etiqueta").asString()).isEqualTo("S" + (i + 1));
            assertThat(LocalDate.parse(serie.get(i).get("desde").asString())).isEqualTo(primera.plusWeeks(i));
        }
    }

    @Test
    void elAcumuladoCuentaDesdeElInicioDeLaObraNoSoloDesdeElPeriodoYNuncaBaja() throws Exception {
        JsonNode serie = ok(ruta("30d"), tokenJefe).get("gastoAcumulado").get("serie");

        double anterior = 0;
        for (JsonNode punto : serie) {
            double valor = punto.get("ejecutadoAcumulado").asDouble();
            assertThat(valor).isGreaterThanOrEqualTo(anterior);
            anterior = valor;
        }
        // La primera semana ya trae lo despachado hace 45 días (5.000), que quedó antes del periodo.
        assertThat(serie.get(0).get("ejecutadoAcumulado").asDouble()).isGreaterThanOrEqualTo(5000);
        // La última semana llega hasta hoy: es el ejecutado total.
        assertThat(serie.get(serie.size() - 1).get("ejecutadoAcumulado").asDouble()).isEqualTo(61500);
    }

    @Test
    void cadaSemanaAcumulaLoOcurridoHastaSuCierre() throws Exception {
        JsonNode serie = ok(ruta("30d"), tokenJefe).get("gastoAcumulado").get("serie");

        for (JsonNode punto : serie) {
            LocalDate cierre = LocalDate.parse(punto.get("desde").asString()).plusDays(6);
            double esperado = esperadoHasta(cierre.isAfter(hoy) ? hoy : cierre);
            assertThat(punto.get("ejecutadoAcumulado").asDouble()).as(punto.get("etiqueta").asString())
                    .isCloseTo(esperado, within(0.01));
        }
    }

    @Test
    void elPeriodoDe7DiasTrae1o2Semanas() throws Exception {
        JsonNode j = ok(ruta("7d"), tokenJefe);

        assertThat(j.get("periodo").asString()).isEqualTo("7d");
        assertThat(LocalDate.parse(j.get("desde").asString())).isEqualTo(hoy.minusDays(6));
        JsonNode serie = j.get("gastoAcumulado").get("serie");
        assertThat(serie.size()).isBetween(1, 2);
        assertThat(serie.get(0).get("etiqueta").asString()).isEqualTo("S1");
        assertThat(serie.get(serie.size() - 1).get("ejecutadoAcumulado").asDouble()).isEqualTo(61500);
    }

    @Test
    void elPeriodoObraEmpiezaEnElPrimerMovimientoDeKardexDeLaObra() throws Exception {
        JsonNode j = ok(ruta("obra"), tokenJefe);

        assertThat(j.get("periodo").asString()).isEqualTo("obra");
        assertThat(LocalDate.parse(j.get("desde").asString())).isEqualTo(hoy.minusDays(50)); // la recepción
        assertThat(j.get("gastoAcumulado").get("serie").size()).isGreaterThan(6);
        assertThat(j.get("gastoAcumulado").get("serie").get(0).get("etiqueta").asString()).isEqualTo("S1");
    }

    @Test
    void unPeriodoQueNoExisteEs400() throws Exception {
        HttpResponse<String> r = get(ruta("90d"), tokenJefe);

        assertThat(r.statusCode()).isEqualTo(400);
        assertThat(json.readTree(r.body()).get("mensaje").asString()).contains("7d", "30d", "obra");
    }

    // ---- por material ----------------------------------------------------

    @Test
    void porMaterialTraeLosMasEjecutadosConSuDesviacionYElUmbral() throws Exception {
        JsonNode j = ok(ruta("30d"), tokenJefe);
        JsonNode porMaterial = j.get("porMaterial");

        assertThat(porMaterial).hasSize(2); // el tornillo está presupuestado pero no se consumió
        JsonNode v = porMaterial.get(0);
        assertThat(v.get("materialId").asLong()).isEqualTo(volcanita.getId());
        assertThat(v.get("sku").asString()).isEqualTo(volcanita.getSku());
        assertThat(v.get("nombre").asString()).isEqualTo(volcanita.getNombre());
        assertThat(v.get("presupuestado").asDouble()).isEqualTo(54000);
        assertThat(v.get("ejecutado").asDouble()).isEqualTo(60000);
        assertThat(v.get("desviacionPct").asDouble()).isCloseTo(11.11, within(0.01));
        assertThat(v.get("superaUmbral").asBoolean()).isTrue();
        JsonNode y = porMaterial.get(1);
        assertThat(y.get("materialId").asLong()).isEqualTo(yeso.getId());
        assertThat(y.get("presupuestado").asDouble()).isZero();
        assertThat(y.get("ejecutado").asDouble()).isEqualTo(1500);
        assertThat(y.get("desviacionPct").isNull()).as("sin presupuesto no hay con qué comparar").isTrue();
        assertThat(y.get("superaUmbral").asBoolean()).isFalse();
    }

    @Test
    void conMasDeCincoMaterialesQuedanLos5MayoresYElRestoVaEnOtros() throws Exception {
        // Siete materiales más, con ejecutado creciente: 100, 200, ... 700.
        for (int i = 1; i <= 7; i++) {
            Material m = material("EXTRA" + i + "-" + s, 100, empresa);
            movimiento(obra, m, TipoMovimiento.DESPACHO, i, hoy);
        }
        JsonNode j = ok(ruta("30d"), tokenJefe);

        JsonNode top = j.get("porMaterial");
        assertThat(top).hasSize(5);
        assertThat(top.get(0).get("ejecutado").asDouble()).isEqualTo(60000);
        for (int i = 1; i < top.size(); i++) {
            assertThat(top.get(i).get("ejecutado").asDouble()).isLessThanOrEqualTo(top.get(i - 1).get("ejecutado").asDouble());
        }
        // Total de materiales con ejecutado: volcanita, yeso y 7 extras = 9; 5 arriba, 4 en "otros".
        JsonNode otros = j.get("otros");
        assertThat(otros.get("cantidad").asInt()).isEqualTo(4);
        double sumaTop = 0;
        for (JsonNode m : top) {
            sumaTop += m.get("ejecutado").asDouble();
        }
        assertThat(sumaTop + otros.get("ejecutado").asDouble())
                .isCloseTo(j.get("gastoAcumulado").get("ejecutadoTotal").asDouble(), within(0.01));
    }

    @Test
    void elEjecutadoValoraAlPrecioCongeladoDelPresupuesto() throws Exception {
        volcanita.setPrecioUnitario(9999);
        yeso.setPrecioUnitario(600);
        materialRepository.save(volcanita);
        materialRepository.save(yeso);

        JsonNode j = ok(ruta("30d"), tokenJefe);

        // Volcanita estaba presupuestada: sigue a 5.000. Yeso no: usa el vigente (600 × 5).
        assertThat(j.get("porMaterial").get(0).get("ejecutado").asDouble()).isEqualTo(60000);
        assertThat(j.get("gastoAcumulado").get("ejecutadoTotal").asDouble()).isEqualTo(63000);
    }

    // ---- obras sin datos -------------------------------------------------

    @Test
    void unaObraSinPresupuestoNoDa500_ConDesviacionNula() throws Exception {
        Obra sinPresupuesto = obra("Sin presupuesto " + s, empresa, jefe, EstadoObra.ACTIVA);
        movimiento(sinPresupuesto, yeso, TipoMovimiento.DESPACHO, 4, hoy);

        JsonNode j = ok("/api/obras/" + sinPresupuesto.getId() + "/metricas/jefe", tokenJefe);

        assertThat(j.get("gastoAcumulado").get("presupuestoTotal").asDouble()).isZero();
        assertThat(j.get("gastoAcumulado").get("ejecutadoTotal").asDouble()).isEqualTo(1200);
        assertThat(j.get("porMaterial").get(0).get("desviacionPct").isNull()).isTrue();
        assertThat(j.get("porMaterial").get(0).get("superaUmbral").asBoolean()).isFalse();
    }

    @Test
    void unaObraSinMovimientosDaSerieEnCeroYListasVacias() throws Exception {
        Obra vacia = obra("Vacía " + s, empresa, jefe, EstadoObra.ACTIVA);

        JsonNode j = ok("/api/obras/" + vacia.getId() + "/metricas/jefe", tokenJefe);

        assertThat(j.get("gastoAcumulado").get("serie").size()).isGreaterThan(0);
        for (JsonNode punto : j.get("gastoAcumulado").get("serie")) {
            assertThat(punto.get("ejecutadoAcumulado").asDouble()).isZero();
        }
        assertThat(j.get("porMaterial")).isEmpty();
        assertThat(j.get("otros").get("cantidad").asInt()).isZero();
        assertThat(j.get("otros").get("ejecutado").asDouble()).isZero();
    }

    @Test
    void elContratoNoTienePorPartida() throws Exception {
        JsonNode j = ok(ruta("30d"), tokenJefe);

        assertThat(j.has("porPartida")).isFalse();
    }

    // ---- acceso ----------------------------------------------------------

    @Test
    void elJefeDeLaObraYElAdminEntran() throws Exception {
        assertThat(get(ruta(null), tokenJefe).statusCode()).isEqualTo(200);
        assertThat(get(ruta(null), tokenAdmin).statusCode()).isEqualTo(200);
    }

    @Test
    void unJefeDeOtraObraDeLaMismaEmpresaNoEntra() throws Exception {
        String otroJefe = token(usuario("jefe2", RolUsuario.JEFE_TERRENO, empresa));

        assertThat(get(ruta(null), otroJefe).statusCode()).isEqualTo(403);
    }

    @Test
    void bodegueroYTrabajadorNoEntran_SinTokenTampoco() throws Exception {
        assertThat(get(ruta(null), tokenBodeguero).statusCode()).isEqualTo(403);
        assertThat(get(ruta(null), tokenTrabajador).statusCode()).isEqualTo(403);
        assertThat(get(ruta(null), null).statusCode()).isIn(401, 403);
    }

    @Test
    void laObraDeOtraEmpresaEs404ComoUnaQueNoExiste() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        String tokenAjeno = token(usuario("admin-b", RolUsuario.ADMIN, otra));

        assertThat(get(ruta(null), tokenAjeno).statusCode()).isEqualTo(404);
        assertThat(get("/api/obras/999999999/metricas/jefe", tokenAjeno).statusCode()).isEqualTo(404);
    }

    // ---------------------------------------------------------------------

    private static LocalDate lunes(LocalDate dia) {
        return dia.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
    }

    /** Lo ejecutado (despacho + consumo, valorado como el presupuesto) hasta ese día inclusive. */
    private double esperadoHasta(LocalDate dia) {
        double total = 0;
        total += hoy.minusDays(45).isAfter(dia) ? 0 : 1 * PRECIO_VOLCANITA;
        total += hoy.minusDays(20).isAfter(dia) ? 0 : 5 * PRECIO_VOLCANITA;
        total += hoy.minusDays(10).isAfter(dia) ? 0 : 4 * PRECIO_VOLCANITA;
        total += hoy.isAfter(dia) ? 0 : 2 * PRECIO_VOLCANITA + 5 * PRECIO_YESO;
        return total;
    }
}
