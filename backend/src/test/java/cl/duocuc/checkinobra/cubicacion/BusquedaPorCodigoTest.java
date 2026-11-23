package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
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
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * C7 (#40): GET /api/materiales/por-codigo/{codigo}, lo que usa el escáner. Acepta el código de
 * barras impreso de fábrica o el SKU de la empresa, sin que quien escanea sepa cuál de los dos
 * está leyendo. Por HTTP, Postgres real.
 *
 * <p>Que el trabajador no vea costos ya lo cubre {@code TrabajadorSinCostosTest} para el SKU; acá
 * se comprueba además por la vía del código de barras, y que el costo sí llega a quien lo maneja.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class BusquedaPorCodigoTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Material volcanita;
    private String tokenBodeguero;

    @BeforeEach
    void prepararElCatalogo() {
        s = UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        volcanita = material("TAB-VOL-" + s, "7801234" + s, empresa);
        tokenBodeguero = token(RolUsuario.BODEGUERO, "bodega", empresa);
    }

    @Test
    void encuentraPorCodigoDeBarras() throws Exception {
        HttpResponse<String> r = buscar("7801234" + s, tokenBodeguero);

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode m = json.readTree(r.body());
        assertThat(m.get("id").asLong()).isEqualTo(volcanita.getId());
        assertThat(m.get("sku").asString()).isEqualTo("TAB-VOL-" + s);
        assertThat(m.get("codigoBarra").asString()).isEqualTo("7801234" + s);
    }

    @Test
    void encuentraPorSku() throws Exception {
        HttpResponse<String> r = buscar("TAB-VOL-" + s, tokenBodeguero);

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(json.readTree(r.body()).get("id").asLong()).isEqualTo(volcanita.getId());
    }

    @Test
    void elSkuNoDistingueMayusculasNiEspaciosAlrededor() throws Exception {
        for (String escrito : new String[] {
                "tab-vol-" + s.toLowerCase(), "Tab-Vol-" + s.toLowerCase(), " TAB-VOL-" + s, "TAB-VOL-" + s + "  ",
                "  tab-vol-" + s.toLowerCase() + " "}) {
            HttpResponse<String> r = buscar(escrito, tokenBodeguero);

            assertThat(r.statusCode()).as("«%s»", escrito).isEqualTo(200);
            assertThat(json.readTree(r.body()).get("id").asLong()).as("«%s»", escrito).isEqualTo(volcanita.getId());
        }
    }

    @Test
    void elCodigoDeBarrasTambienAdmiteEspaciosAlrededor() throws Exception {
        HttpResponse<String> r = buscar("  7801234" + s + " ", tokenBodeguero);

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(json.readTree(r.body()).get("id").asLong()).isEqualTo(volcanita.getId());
    }

    @Test
    void siUnCodigoDeBarrasCoincideConElSkuDeOtroMaterialGanaElCodigoDeBarras() throws Exception {
        Material otro = material("OTRO-" + s, "TAB-VOL-" + s, empresa);
        // El SKU "TAB-VOL-x" es de la volcanita; el código de barras "TAB-VOL-x" es del otro.
        HttpResponse<String> r = buscar("TAB-VOL-" + s, tokenBodeguero);

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(json.readTree(r.body()).get("id").asLong()).isEqualTo(otro.getId());
    }

    // ---- no encontrado ---------------------------------------------------

    @Test
    void unCodigoQueNoExisteEs404ConUnMensajeClaro() throws Exception {
        HttpResponse<String> r = buscar("NO-EXISTE-" + s, tokenBodeguero);

        assertThat(r.statusCode()).isEqualTo(404);
        JsonNode cuerpo = json.readTree(r.body());
        assertThat(cuerpo.get("mensaje").asString()).containsIgnoringCase("código no reconocido");
        assertThat(r.body()).as("sin trazas ni nombres internos").doesNotContain("Exception", "cl.duocuc");
    }

    @Test
    void unCodigoEnBlancoNoEsUnError500() throws Exception {
        HttpResponse<String> r = buscar("  ", tokenBodeguero);

        assertThat(r.statusCode()).isIn(400, 404);
    }

    // ---- aislamiento entre empresas --------------------------------------

    @Test
    void elCodigoDeOtraEmpresaEs404ParaElSkuYParaElCodigoDeBarras() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        material("CEM-" + s, "7809999" + s, otra);
        String tokenAjeno = token(RolUsuario.BODEGUERO, "bodega-b", otra);

        // La empresa de la volcanita no ve el cemento de la otra, ni por SKU ni por código de barras...
        assertThat(buscar("CEM-" + s, tokenBodeguero).statusCode()).isEqualTo(404);
        assertThat(buscar("7809999" + s, tokenBodeguero).statusCode()).isEqualTo(404);
        // ...ni la otra ve la volcanita.
        assertThat(buscar("TAB-VOL-" + s, tokenAjeno).statusCode()).isEqualTo(404);
        assertThat(buscar("7801234" + s, tokenAjeno).statusCode()).isEqualTo(404);
    }

    @Test
    void conElMismoCodigoEnDosEmpresasCadaEscanerResuelveElSuyo() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        Material suyo = material("TAB-VOL-" + s, "7801234" + s, otra);
        String tokenOtra = token(RolUsuario.BODEGUERO, "bodega-b", otra);

        JsonNode deA = json.readTree(buscar("7801234" + s, tokenBodeguero).body());
        JsonNode deB = json.readTree(buscar("7801234" + s, tokenOtra).body());

        assertThat(deA.get("id").asLong()).isEqualTo(volcanita.getId());
        assertThat(deB.get("id").asLong()).isEqualTo(suyo.getId());
        assertThat(deA.get("id").asLong()).isNotEqualTo(deB.get("id").asLong());
    }

    // ---- quién y qué ve ---------------------------------------------------

    @Test
    void elTrabajadorEncuentraPorCodigoDeBarrasPeroSinPrecioNiCostos() throws Exception {
        String tokenTrabajador = token(RolUsuario.TRABAJADOR, "trab", empresa);

        HttpResponse<String> r = buscar("7801234" + s, tokenTrabajador);

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(json.readTree(r.body()).get("id").asLong()).isEqualTo(volcanita.getId());
        for (String campo : new String[] {
                "precioUnitario", "ultimoCostoUnitario", "fechaUltimoCosto", "costoPromedio"}) {
            assertThat(r.body()).as("el trabajador no debe ver %s", campo).doesNotContain("\"" + campo + "\"");
        }
    }

    @Test
    void elAdminSiVeElPrecio() throws Exception {
        String tokenAdmin = token(RolUsuario.ADMIN, "admin", empresa);

        JsonNode m = json.readTree(buscar("tab-vol-" + s.toLowerCase(), tokenAdmin).body());

        assertThat(m.has("precioUnitario")).isTrue();
        assertThat(m.get("precioUnitario").asDouble()).isEqualTo(5980);
    }

    @Test
    void sinTokenNoSeBusca() throws Exception {
        HttpResponse<String> r = http.send(HttpRequest.newBuilder(URI.create(
                "http://localhost:" + puerto + "/api/materiales/por-codigo/TAB-VOL-" + s)).GET().build(),
                HttpResponse.BodyHandlers.ofString());

        assertThat(r.statusCode()).isIn(401, 403);
    }

    // ---------------------------------------------------------------------

    /** Los espacios del código van codificados en la URL, como los manda la app. */
    private HttpResponse<String> buscar(String codigo, String token) throws Exception {
        HttpRequest r = HttpRequest.newBuilder(URI.create(
                        "http://localhost:" + puerto + "/api/materiales/por-codigo/" + codigo.replace(" ", "%20")))
                .header("Authorization", "Bearer " + token).GET().build();
        return http.send(r, HttpResponse.BodyHandlers.ofString());
    }

    private Material material(String sku, String codigoBarra, Empresa deLaEmpresa) {
        return materialRepository.save(Material.builder()
                .sku(sku).codigoBarra(codigoBarra).nombre("Volcanita ST 10 mm " + sku)
                .categoria(CategoriaMaterial.VOLCANITA).precioUnitario(5980).stockMinimo(0).empresa(deLaEmpresa)
                .build());
    }

    private String token(RolUsuario rol, String nombre, Empresa deLaEmpresa) {
        return jwtService.emitir(usuarioRepository.save(Usuario.builder()
                .nombre(nombre + "-" + s).email(nombre + "-" + s + "-" + UUID.randomUUID() + "@test.cl")
                .rol(rol).empresa(deLaEmpresa).build()));
    }
}
