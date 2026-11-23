package cl.duocuc.checkinobra.presupuesto;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.ItemCubicado;
import cl.duocuc.checkinobra.cubicacion.ItemCubicadoRepository;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialRepository;
import cl.duocuc.checkinobra.cubicacion.ParametroMerma;
import cl.duocuc.checkinobra.cubicacion.ParametroMermaRepository;
import cl.duocuc.checkinobra.cubicacion.Partida;
import cl.duocuc.checkinobra.cubicacion.PartidaRepository;
import cl.duocuc.checkinobra.cubicacion.TipoPartida;
import cl.duocuc.checkinobra.inventario.KardexMovimiento;
import cl.duocuc.checkinobra.inventario.KardexMovimientoRepository;
import cl.duocuc.checkinobra.inventario.TipoMovimiento;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/**
 * D8/D9 (#52, #53): GET /api/presupuestos/{id}/desviacion, con el desglose por material, el umbral
 * y la merma estimada contra la real. Por HTTP contra el servidor de verdad y Postgres real.
 *
 * Escenario base (precios de catálogo: volcanita 5000, tornillo 10, yeso 300):
 *   presupuesto congelado: volcanita 10,8 u (54.000) + tornillo 100 u (1.000) = 55.000
 *   kardex de la obra: volcanita 12 u (despacho 10 + consumo 2), yeso 5 u (sin presupuestar),
 *                      una recepción de volcanita que NO cuenta como ejecutado
 *   ejecutado = 12 × 5.000 + 5 × 300 = 61.500  →  +6.500 (11,82 %)
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class DesviacionTest {

    private static final double PRECIO_VOLCANITA = 5000;
    private static final double PRECIO_TORNILLO = 10;
    private static final double PRECIO_YESO = 300;

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private PartidaRepository partidaRepository;
    @Autowired private ItemCubicadoRepository itemCubicadoRepository;
    @Autowired private ParametroMermaRepository parametroMermaRepository;
    @Autowired private PresupuestoRepository presupuestoRepository;
    @Autowired private PresupuestoItemRepository presupuestoItemRepository;
    @Autowired private KardexMovimientoRepository kardexMovimientoRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Usuario jefe;
    private String tokenJefe;
    private Obra obra;
    private Material volcanita;
    private Material tornillo;
    private Material yeso;
    private Presupuesto presupuesto;

    @BeforeEach
    void prepararElEscenario() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Empresa " + s).rut("R-" + s).build());
        jefe = usuario("jefe-" + s, RolUsuario.JEFE_TERRENO, empresa);
        tokenJefe = jwtService.emitir(jefe);
        obra = obra("Edificio " + s, empresa);
        volcanita = material("VOL-" + s, PRECIO_VOLCANITA, empresa);
        tornillo = material("TOR-" + s, PRECIO_TORNILLO, empresa);
        yeso = material("YES-" + s, PRECIO_YESO, empresa);

        presupuesto = presupuestoCongelado(obra, item(volcanita, 10.8), item(tornillo, 100));
        parametroMermaRepository.save(ParametroMerma.builder().material(volcanita).porcentaje(8).build());
        cubicar(obra, volcanita, 10, 10.8);

        movimiento(obra, volcanita, TipoMovimiento.RECEPCION, 50);
        movimiento(obra, volcanita, TipoMovimiento.DESPACHO, 10);
        movimiento(obra, volcanita, TipoMovimiento.CONSUMO, 2);
        movimiento(obra, yeso, TipoMovimiento.RECEPCION, 20);
        movimiento(obra, yeso, TipoMovimiento.DESPACHO, 5);
    }

    // ---- totales ---------------------------------------------------------

    @Test
    void elTotalTraeMontoPorcentajeYUmbralSinPerderLosCuatroCamposDeSiempre() throws Exception {
        HttpResponse<String> r = desviacion(presupuesto.getId(), tokenJefe);

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode j = json.readTree(r.body());
        assertThat(j.get("presupuestado").asDouble()).isEqualTo(55000);
        assertThat(j.get("ejecutado").asDouble()).isEqualTo(61500);
        assertThat(j.get("desviacionPct").asDouble()).isCloseTo(11.82, within(0.01));
        assertThat(j.has("mermaRealVsEstimada")).isTrue();
        assertThat(j.get("desviacionMonto").asDouble()).isEqualTo(6500);
        assertThat(j.get("umbralPct").asDouble()).isEqualTo(10);
        assertThat(j.get("superaUmbral").asBoolean()).isTrue();
    }

    @Test
    void dentroDelUmbralNoLoSupera_yJustoEnElUmbralTampoco() throws Exception {
        Obra otra = obra("Casa " + s, empresa);
        Presupuesto p = presupuestoCongelado(otra, item(volcanita, 10));
        movimiento(otra, volcanita, TipoMovimiento.RECEPCION, 50);
        movimiento(otra, volcanita, TipoMovimiento.DESPACHO, 10.4);

        JsonNode dentro = json.readTree(desviacion(p.getId(), tokenJefe).body());
        assertThat(dentro.get("desviacionPct").asDouble()).isCloseTo(4, within(0.01));
        assertThat(dentro.get("superaUmbral").asBoolean()).isFalse();

        movimiento(otra, volcanita, TipoMovimiento.CONSUMO, 0.6); // 11 u en total: justo +10 %
        JsonNode justo = json.readTree(desviacion(p.getId(), tokenJefe).body());
        assertThat(justo.get("desviacionPct").asDouble()).isCloseTo(10, within(0.01));
        assertThat(justo.get("superaUmbral").asBoolean()).as("solo supera si es MAYOR al umbral").isFalse();

        movimiento(otra, volcanita, TipoMovimiento.CONSUMO, 0.5);
        JsonNode fuera = json.readTree(desviacion(p.getId(), tokenJefe).body());
        assertThat(fuera.get("superaUmbral").asBoolean()).isTrue();
    }

    @Test
    void gastarMenosDeLoPresupuestadoNoEsSobrecosto() throws Exception {
        Obra otra = obra("Galpon " + s, empresa);
        Presupuesto p = presupuestoCongelado(otra, item(volcanita, 10));
        movimiento(otra, volcanita, TipoMovimiento.RECEPCION, 50);
        movimiento(otra, volcanita, TipoMovimiento.DESPACHO, 2);

        JsonNode j = json.readTree(desviacion(p.getId(), tokenJefe).body());

        assertThat(j.get("desviacionMonto").asDouble()).isEqualTo(-40000);
        assertThat(j.get("desviacionPct").asDouble()).isCloseTo(-80, within(0.01));
        assertThat(j.get("superaUmbral").asBoolean()).isFalse();
    }

    @Test
    void unPresupuestoEnCeroDaDesviacionCeroYSinMateriales() throws Exception {
        Obra vacia = obra("Vacia " + s, empresa);
        Presupuesto p = presupuestoRepository.save(
                Presupuesto.builder().estado(EstadoPresupuesto.CONGELADO).total(0).obra(vacia).build());

        HttpResponse<String> r = desviacion(p.getId(), tokenJefe);

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode j = json.readTree(r.body());
        assertThat(j.get("presupuestado").asDouble()).isZero();
        assertThat(j.get("ejecutado").asDouble()).isZero();
        assertThat(j.get("desviacionPct").asDouble()).isZero();
        assertThat(j.get("desviacionMonto").asDouble()).isZero();
        assertThat(j.get("superaUmbral").asBoolean()).isFalse();
        assertThat(j.get("materiales")).isEmpty();
    }

    @Test
    void conPresupuestoEnCeroPeroConConsumoElPorcentajeSigueEnCeroYElMontoMuestraLoGastado() throws Exception {
        Obra sinPresupuestar = obra("Sin presupuestar " + s, empresa);
        Presupuesto p = presupuestoRepository.save(
                Presupuesto.builder().estado(EstadoPresupuesto.CONGELADO).total(0).obra(sinPresupuestar).build());
        movimiento(sinPresupuestar, yeso, TipoMovimiento.RECEPCION, 10);
        movimiento(sinPresupuestar, yeso, TipoMovimiento.DESPACHO, 4);

        JsonNode j = json.readTree(desviacion(p.getId(), tokenJefe).body());

        assertThat(j.get("desviacionPct").asDouble()).isZero();
        assertThat(j.get("desviacionMonto").asDouble()).isEqualTo(1200);
        assertThat(j.get("superaUmbral").asBoolean()).isFalse();
        assertThat(j.get("materiales")).hasSize(1);
    }

    // ---- por material ----------------------------------------------------

    @Test
    void cadaMaterialTraeSuCantidadMontoYDesviacion() throws Exception {
        JsonNode materiales = json.readTree(desviacion(presupuesto.getId(), tokenJefe).body()).get("materiales");

        JsonNode v = porMaterial(materiales, volcanita);
        assertThat(v.get("sku").asString()).isEqualTo(volcanita.getSku());
        assertThat(v.get("nombre").asString()).isEqualTo(volcanita.getNombre());
        assertThat(v.has("unidad")).as("el catálogo no tiene unidad: la clave viene, en null").isTrue();
        assertThat(v.get("unidad").isNull()).isTrue();
        assertThat(v.get("cantidadPresupuestada").asDouble()).isEqualTo(10.8);
        assertThat(v.get("cantidadEjecutada").asDouble()).isEqualTo(12);
        assertThat(v.get("montoPresupuestado").asDouble()).isEqualTo(54000);
        assertThat(v.get("montoEjecutado").asDouble()).isEqualTo(60000);
        assertThat(v.get("desviacionMonto").asDouble()).isEqualTo(6000);
        assertThat(v.get("desviacionPct").asDouble()).isCloseTo(11.11, within(0.01));
        assertThat(v.get("superaUmbral").asBoolean()).isTrue();
    }

    @Test
    void unMaterialConsumidoSinPresupuestoAparece_conPorcentajeNulo() throws Exception {
        JsonNode materiales = json.readTree(desviacion(presupuesto.getId(), tokenJefe).body()).get("materiales");

        JsonNode y = porMaterial(materiales, yeso);

        assertThat(y.get("montoPresupuestado").asDouble()).isZero();
        assertThat(y.get("cantidadPresupuestada").asDouble()).isZero();
        assertThat(y.get("cantidadEjecutada").asDouble()).isEqualTo(5);
        assertThat(y.get("montoEjecutado").asDouble()).isEqualTo(1500);
        assertThat(y.get("desviacionMonto").asDouble()).isEqualTo(1500);
        assertThat(y.get("desviacionPct").isNull()).isTrue();
        assertThat(y.get("superaUmbral").asBoolean()).isFalse();
    }

    @Test
    void unMaterialPresupuestadoSinConsumoApareceConTodoLoPorEjecutar() throws Exception {
        JsonNode materiales = json.readTree(desviacion(presupuesto.getId(), tokenJefe).body()).get("materiales");

        JsonNode t = porMaterial(materiales, tornillo);

        assertThat(t.get("cantidadEjecutada").asDouble()).isZero();
        assertThat(t.get("montoEjecutado").asDouble()).isZero();
        assertThat(t.get("montoPresupuestado").asDouble()).isEqualTo(1000);
        assertThat(t.get("desviacionMonto").asDouble()).isEqualTo(-1000);
        assertThat(t.get("desviacionPct").asDouble()).isCloseTo(-100, within(0.01));
        assertThat(t.get("superaUmbral").asBoolean()).isFalse();
    }

    @Test
    void losMaterialesVienenOrdenadosPorElMayorDesvioEnValorAbsoluto() throws Exception {
        JsonNode materiales = json.readTree(desviacion(presupuesto.getId(), tokenJefe).body()).get("materiales");

        assertThat(materiales).hasSize(3);
        assertThat(materiales.get(0).get("materialId").asLong()).isEqualTo(volcanita.getId()); // +6.000
        assertThat(materiales.get(1).get("materialId").asLong()).isEqualTo(yeso.getId());      // +1.500
        assertThat(materiales.get(2).get("materialId").asLong()).isEqualTo(tornillo.getId());  // -1.000
    }

    @Test
    void elEjecutadoValoraAlPrecioCongeladoDelPresupuestoYNoAlDelCatalogoDeHoy() throws Exception {
        volcanita.setPrecioUnitario(9999);
        yeso.setPrecioUnitario(600);
        materialRepository.save(volcanita);
        materialRepository.save(yeso);

        JsonNode j = json.readTree(desviacion(presupuesto.getId(), tokenJefe).body());
        JsonNode materiales = j.get("materiales");

        // La volcanita estaba en el presupuesto: se valora con el precio con que se presupuestó (5.000).
        assertThat(porMaterial(materiales, volcanita).get("montoEjecutado").asDouble()).isEqualTo(60000);
        // El yeso no estaba: no hay precio congelado, se usa el vigente del catálogo.
        assertThat(porMaterial(materiales, yeso).get("montoEjecutado").asDouble()).isEqualTo(3000);
        assertThat(j.get("ejecutado").asDouble()).isEqualTo(63000);
    }

    // ---- merma -----------------------------------------------------------

    @Test
    void laMermaEstimadaEsLaDelCatalogoYLaRealSaleDeLoEjecutadoContraLoNetoCubicado() throws Exception {
        JsonNode materiales = json.readTree(desviacion(presupuesto.getId(), tokenJefe).body()).get("materiales");

        JsonNode v = porMaterial(materiales, volcanita);

        assertThat(v.get("mermaEstimadaPct").asDouble()).isEqualTo(8);
        assertThat(v.get("mermaRealPct").asDouble()).isCloseTo(20, within(0.01)); // 12 / 10 - 1
    }

    @Test
    void sinParametroDeMermaOSinCubicacionLaMermaVieneNula() throws Exception {
        JsonNode materiales = json.readTree(desviacion(presupuesto.getId(), tokenJefe).body()).get("materiales");

        JsonNode y = porMaterial(materiales, yeso);

        assertThat(y.get("mermaEstimadaPct").isNull()).isTrue();
        assertThat(y.get("mermaRealPct").isNull()).isTrue();
    }

    @Test
    void laNetaCubicadaSumaTodasLasPartidasDeLaObra() throws Exception {
        cubicar(obra, volcanita, 5, 5.4); // neta total 15; ejecutado 12 → -20 %

        JsonNode materiales = json.readTree(desviacion(presupuesto.getId(), tokenJefe).body()).get("materiales");

        assertThat(porMaterial(materiales, volcanita).get("mermaRealPct").asDouble()).isCloseTo(-20, within(0.01));
    }

    // ---- acceso y aislamiento --------------------------------------------

    @Test
    void elPresupuestoDeOtraEmpresaEsUn404() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        String tokenAjeno = jwtService.emitir(usuario("jefe-b-" + s, RolUsuario.JEFE_TERRENO, otra));

        assertThat(desviacion(presupuesto.getId(), tokenAjeno).statusCode()).isEqualTo(404);
    }

    @Test
    void unPresupuestoQueNoExisteEsUn404() throws Exception {
        assertThat(desviacion(999_999_999L, tokenJefe).statusCode()).isEqualTo(404);
    }

    @Test
    void elTrabajadorNoVeLaDesviacion_ElBodegueroYElAdminSi() throws Exception {
        String trabajador = jwtService.emitir(usuario("trab-" + s, RolUsuario.TRABAJADOR, empresa));
        String bodeguero = jwtService.emitir(usuario("bod-" + s, RolUsuario.BODEGUERO, empresa));
        String admin = jwtService.emitir(usuario("adm-" + s, RolUsuario.ADMIN, empresa));

        assertThat(desviacion(presupuesto.getId(), trabajador).statusCode()).isEqualTo(403);
        assertThat(desviacion(presupuesto.getId(), bodeguero).statusCode()).isEqualTo(200);
        assertThat(desviacion(presupuesto.getId(), admin).statusCode()).isEqualTo(200);
    }

    @Test
    void sinTokenEsUn401() throws Exception {
        HttpRequest r = HttpRequest.newBuilder(URI.create(
                "http://localhost:" + puerto + "/api/presupuestos/" + presupuesto.getId() + "/desviacion")).GET().build();

        assertThat(http.send(r, HttpResponse.BodyHandlers.ofString()).statusCode()).isIn(401, 403);
    }

    // ---------------------------------------------------------------------

    private static JsonNode porMaterial(JsonNode materiales, Material m) {
        for (JsonNode f : materiales) {
            if (f.get("materialId").asLong() == m.getId()) {
                return f;
            }
        }
        throw new AssertionError("No hay fila del material " + m.getSku());
    }

    private PresupuestoItem item(Material m, double cantidad) {
        return PresupuestoItem.builder().material(m).cantidad(cantidad)
                .precioUnitario(m.getPrecioUnitario()).subtotal(cantidad * m.getPrecioUnitario()).build();
    }

    private Presupuesto presupuestoCongelado(Obra deLaObra, PresupuestoItem... items) {
        double total = List.of(items).stream().mapToDouble(PresupuestoItem::getSubtotal).sum();
        Presupuesto p = presupuestoRepository.save(
                Presupuesto.builder().estado(EstadoPresupuesto.CONGELADO).total(total).obra(deLaObra).build());
        for (PresupuestoItem i : items) {
            i.setPresupuesto(p);
            presupuestoItemRepository.save(i);
        }
        return p;
    }

    private void cubicar(Obra deLaObra, Material m, double neta, double conMerma) {
        Partida partida = partidaRepository.save(Partida.builder()
                .tipo(TipoPartida.TABIQUE).anchoM(4).altoM(2.4).separacionMontantes(0.6).obra(deLaObra).build());
        itemCubicadoRepository.save(ItemCubicado.builder()
                .partida(partida).material(m).cantidadCalculada(neta).cantidadConMerma(conMerma).build());
    }

    private void movimiento(Obra deLaObra, Material m, TipoMovimiento tipo, double cantidad) {
        kardexMovimientoRepository.save(KardexMovimiento.builder()
                .tipoMovimiento(tipo).cantidad(cantidad).fecha(LocalDateTime.now())
                .obra(deLaObra).material(m).usuario(jefe).build());
    }

    private Material material(String sku, double precio, Empresa deLaEmpresa) {
        return materialRepository.save(Material.builder()
                .sku(sku).nombre("Material " + sku).categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(precio).stockMinimo(0).empresa(deLaEmpresa).build());
    }

    private Usuario usuario(String nombre, RolUsuario rol, Empresa deLaEmpresa) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(deLaEmpresa).build());
    }

    private Obra obra(String nombre, Empresa deLaEmpresa) {
        return obraRepository.save(Obra.builder()
                .nombre(nombre).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(deLaEmpresa).build());
    }

    private HttpResponse<String> desviacion(Long presupuestoId, String token) throws Exception {
        HttpRequest r = HttpRequest.newBuilder(URI.create(
                        "http://localhost:" + puerto + "/api/presupuestos/" + presupuestoId + "/desviacion"))
                .header("Authorization", "Bearer " + token).GET().build();
        return http.send(r, HttpResponse.BodyHandlers.ofString());
    }
}
