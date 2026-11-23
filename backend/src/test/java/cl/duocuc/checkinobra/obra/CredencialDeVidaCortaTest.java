package cl.duocuc.checkinobra.obra;

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
import java.time.Duration;
import java.time.Instant;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG13 (#101, S-27): la credencial del trabajador ya no es un QR fijo sino un código de vida corta
 * emitido por el servidor. El bodeguero escanea ese código; el UUID de siempre no sirve para escanear.
 *
 * <pre>
 *   POST /api/trabajadores/yo/credencial/codigo       (TRABAJADOR)  → {codigo, expiraEn, vigenciaSegundos}
 *   GET  /api/trabajadores/por-credencial/{codigo}    (bodega)      → el trabajador, 409 CREDENCIAL_CADUCADA, 404
 * </pre>
 *
 * Por HTTP contra el servidor de verdad y Postgres real.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class CredencialDeVidaCortaTest {

    /** Alfabeto sin 0/O/1/I, de 8 caracteres. */
    private static final String FORMATO_DEL_CODIGO = "[A-HJ-NP-Z2-9]{8}";
    private static final int VIGENCIA_POR_DEFECTO_SEGUNDOS = 120;

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private CodigoCredencialRepository codigoCredencialRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Cuadrilla cuadrilla;
    private Trabajador yo;
    private Trabajador companero;
    private String tokenYo;
    private String tokenCompanero;
    private String tokenBodeguero;

    @BeforeEach
    void prepararLaCuadrilla() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        Obra obra = obraRepository.save(Obra.builder()
                .nombre("Edificio " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
        cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        yo = trabajador("maestro-" + s, empresa);
        companero = trabajador("companero-" + s, empresa);
        tokenYo = jwtService.emitir(yo.getUsuario());
        tokenCompanero = jwtService.emitir(companero.getUsuario());
        tokenBodeguero = token(RolUsuario.BODEGUERO, "bodega", empresa);
    }

    // ---- emitir ----------------------------------------------------------

    @Test
    void elTrabajadorPideUnCodigoDeOchoCaracteresConSuVigencia() throws Exception {
        Instant antes = Instant.now();

        HttpResponse<String> r = pedirCodigo(tokenYo);

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode j = json.readTree(r.body());
        assertThat(j.get("codigo").asString()).matches(FORMATO_DEL_CODIGO);
        assertThat(j.get("vigenciaSegundos").asInt()).isEqualTo(VIGENCIA_POR_DEFECTO_SEGUNDOS);
        Instant expira = Instant.parse(j.get("expiraEn").asString());
        assertThat(Duration.between(antes, expira).toSeconds())
                .isBetween((long) VIGENCIA_POR_DEFECTO_SEGUNDOS - 2, (long) VIGENCIA_POR_DEFECTO_SEGUNDOS + 5);
    }

    @Test
    void elCodigoQuedaGuardadoEnElServidorConSuExpiracionYSuTrabajador() throws Exception {
        String codigo = codigoNuevo(tokenYo);

        CodigoCredencial guardado = codigoCredencialRepository.findByCodigo(codigo).orElseThrow();

        assertThat(guardado.getTrabajador().getId()).isEqualTo(yo.getId());
        assertThat(guardado.getExpiraEn()).isAfter(Instant.now());
        assertThat(guardado.empresaId()).isEqualTo(empresa.getId());
    }

    @Test
    void elAlfabetoNoTieneCaracteresAmbiguos() throws Exception {
        Set<String> vistos = new HashSet<>();
        for (int i = 0; i < 40; i++) {
            String codigo = codigoNuevo(tokenYo);
            assertThat(codigo).matches(FORMATO_DEL_CODIGO).doesNotContainPattern("[01IO]");
            vistos.add(codigo);
        }
        assertThat(vistos).as("cada pedido emite uno distinto").hasSize(40);
    }

    @Test
    void cadaPedidoEmiteUnoNuevoYLosAnterioresSiguenValidosHastaQueVencen() throws Exception {
        String primero = codigoNuevo(tokenYo);
        String segundo = codigoNuevo(tokenYo);

        assertThat(segundo).isNotEqualTo(primero);
        assertThat(escanear(primero, tokenBodeguero).statusCode()).isEqualTo(200);
        assertThat(escanear(segundo, tokenBodeguero).statusCode()).isEqualTo(200);
    }

    // ---- escanear --------------------------------------------------------

    @Test
    void elBodegueroResuelveUnCodigoVigenteAlTrabajadorQueLoPidio() throws Exception {
        String codigo = codigoNuevo(tokenYo);

        HttpResponse<String> r = escanear(codigo, tokenBodeguero);

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode t = json.readTree(r.body());
        assertThat(t.get("id").asLong()).isEqualTo(yo.getId());
        assertThat(t.get("nombre").asString()).isEqualTo(yo.getUsuario().getNombre());
        assertThat(t.has("credencialQr")).as("la respuesta no devuelve credenciales").isFalse();
    }

    @Test
    void bodegueroAdminYJefePuedenEscanearPeroNoElTrabajador() throws Exception {
        String codigo = codigoNuevo(tokenYo);

        assertThat(escanear(codigo, token(RolUsuario.ADMIN, "admin", empresa)).statusCode()).isEqualTo(200);
        assertThat(escanear(codigo, token(RolUsuario.JEFE_TERRENO, "jefe", empresa)).statusCode()).isEqualTo(200);
        assertThat(escanear(codigo, tokenCompanero).statusCode()).isEqualTo(403);
    }

    @Test
    void elCodigoSeComparaSinDistinguirMayusculasNiGuionesNiEspacios() throws Exception {
        String codigo = codigoNuevo(tokenYo);
        String conGuion = codigo.substring(0, 4) + "-" + codigo.substring(4);

        for (String escrito : new String[] {
                codigo.toLowerCase(), conGuion, conGuion.toLowerCase(), " " + codigo + " ",
                codigo.substring(0, 4) + " " + codigo.substring(4), "  " + conGuion.toLowerCase() + "  "}) {
            HttpResponse<String> r = escanear(escrito, tokenBodeguero);

            assertThat(r.statusCode()).as("«%s»", escrito).isEqualTo(200);
            assertThat(json.readTree(r.body()).get("id").asLong()).as("«%s»", escrito).isEqualTo(yo.getId());
        }
    }

    @Test
    void unCodigoVencidoEsUn409CredencialCaducada() throws Exception {
        String vencido = CodigosDePrueba.unico();
        codigoCredencialRepository.save(CodigoCredencial.builder()
                .codigo(vencido).trabajador(yo)
                .creadoEn(Instant.now().minusSeconds(300)).expiraEn(Instant.now().minusSeconds(60)).build());

        HttpResponse<String> r = escanear(vencido, tokenBodeguero);

        assertThat(r.statusCode()).isEqualTo(409);
        JsonNode cuerpo = json.readTree(r.body());
        assertThat(cuerpo.get("codigo").asString()).isEqualTo("CREDENCIAL_CADUCADA");
        // La app lo muestra tal cual: tiene que decir qué hacer.
        assertThat(cuerpo.get("mensaje").asString()).containsIgnoringCase("venci").containsIgnoringCase("trabajador");
    }

    @Test
    void unCodigoQueNoExisteEs404() throws Exception {
        HttpResponse<String> r = escanear("ZZZZ9999", tokenBodeguero);

        assertThat(r.statusCode()).isEqualTo(404);
        assertThat(json.readTree(r.body()).get("mensaje").asString()).containsIgnoringCase("credencial no reconocida");
    }

    @Test
    void elUuidFijoDeAntesYaNoSirveParaEscanear() throws Exception {
        String uuidDeSiempre = trabajadorRepository.findById(yo.getId()).orElseThrow().getCredencialQr();
        assertThat(uuidDeSiempre).as("sigue existiendo internamente").isNotBlank();

        assertThat(escanear(uuidDeSiempre, tokenBodeguero).statusCode()).isEqualTo(404);
    }

    @Test
    void cualquierOtraCosaQueNoTengaElFormatoEs404SinTocarLaBase() throws Exception {
        for (String basura : new String[] {"", "%20", "ABC", "ABCD23456", "ABCD234!", "0O1I0O1I", "' OR 1=1 --"}) {
            HttpResponse<String> r = escanear(basura, tokenBodeguero);

            assertThat(r.statusCode()).as("«%s»", basura).isIn(400, 404);
            assertThat(r.body()).as("«%s»", basura).doesNotContain("Exception", "cl.duocuc");
        }
    }

    @Test
    void elCodigoDeOtraEmpresaEs404EsteVigenteOVencido() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        Trabajador deOtra = trabajador("ajeno-" + s, otra);
        String vigente = codigoNuevo(jwtService.emitir(deOtra.getUsuario()));
        String vencidoAjeno = CodigosDePrueba.unico();
        codigoCredencialRepository.save(CodigoCredencial.builder()
                .codigo(vencidoAjeno).trabajador(deOtra)
                .creadoEn(Instant.now().minusSeconds(300)).expiraEn(Instant.now().minusSeconds(60)).build());

        assertThat(escanear(vigente, tokenBodeguero).statusCode()).isEqualTo(404);
        // Un vencido ajeno tampoco delata que existe: 404 y no el 409 de "caducada".
        assertThat(escanear(vencidoAjeno, tokenBodeguero).statusCode()).isEqualTo(404);
        // Y para su propia empresa sí funciona.
        assertThat(escanear(vigente, token(RolUsuario.BODEGUERO, "bodega-b", otra)).statusCode()).isEqualTo(200);
    }

    // ---- renovar revoca --------------------------------------------------

    @Test
    void renovarLaCredencialRevocaLosCodigosVigentesDelTrabajador() throws Exception {
        String primero = codigoNuevo(tokenYo);
        String segundo = codigoNuevo(tokenYo);
        String delCompanero = codigoNuevo(tokenCompanero);

        HttpResponse<String> renovada = llamar("PUT", "/api/trabajadores/yo/credencial", tokenYo);

        assertThat(renovada.statusCode()).isEqualTo(200);
        assertThat(renovada.body()).doesNotContain("credencialQr");
        assertThat(escanear(primero, tokenBodeguero).statusCode()).isEqualTo(404);
        assertThat(escanear(segundo, tokenBodeguero).statusCode()).isEqualTo(404);
        assertThat(escanear(delCompanero, tokenBodeguero).statusCode()).as("el compañero no se toca").isEqualTo(200);
        // Y después de renovar se puede pedir uno nuevo, que sí sirve.
        assertThat(escanear(codigoNuevo(tokenYo), tokenBodeguero).statusCode()).isEqualTo(200);
    }

    @Test
    void cuandoElAdminRenuevaLaDeUnTrabajadorTambienSeRevocanSusCodigos() throws Exception {
        String codigo = codigoNuevo(tokenYo);

        HttpResponse<String> r = llamar("PUT", "/api/trabajadores/" + yo.getId() + "/credencial",
                token(RolUsuario.ADMIN, "admin", empresa));

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(r.body()).doesNotContain("credencialQr");
        assertThat(escanear(codigo, tokenBodeguero).statusCode()).isEqualTo(404);
    }

    // ---- quién puede pedir ----------------------------------------------

    @Test
    void soloElTrabajadorPideCodigosYSiempreLosSuyos() throws Exception {
        assertThat(pedirCodigo(tokenBodeguero).statusCode()).isEqualTo(403);
        assertThat(pedirCodigo(token(RolUsuario.ADMIN, "admin", empresa)).statusCode()).isEqualTo(403);
        assertThat(pedirCodigo(token(RolUsuario.JEFE_TERRENO, "jefe", empresa)).statusCode()).isEqualTo(403);

        String mio = codigoNuevo(tokenYo);
        String delCompanero = codigoNuevo(tokenCompanero);
        assertThat(json.readTree(escanear(mio, tokenBodeguero).body()).get("id").asLong()).isEqualTo(yo.getId());
        assertThat(json.readTree(escanear(delCompanero, tokenBodeguero).body()).get("id").asLong())
                .isEqualTo(companero.getId());
    }

    @Test
    void noHayRutaParaPedirElCodigoDeOtro() throws Exception {
        HttpResponse<String> r = llamar("POST", "/api/trabajadores/" + companero.getId() + "/credencial/codigo", tokenYo);

        assertThat(r.statusCode()).isIn(403, 404, 405);
        assertThat(codigoCredencialRepository.findByTrabajadorId(companero.getId())).isEmpty();
    }

    @Test
    void sinTokenNoSePideNiSeEscanea() throws Exception {
        assertThat(llamar("POST", "/api/trabajadores/yo/credencial/codigo", null).statusCode()).isIn(401, 403);
        assertThat(llamar("GET", "/api/trabajadores/por-credencial/ABCD2345", null).statusCode()).isIn(401, 403);
    }

    // ---- ya no se expone el UUID ----------------------------------------

    @Test
    void laFichaPropiaYaNoTraeElUuidDeLaCredencial() throws Exception {
        HttpResponse<String> r = llamar("GET", "/api/trabajadores/yo", tokenYo);

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(r.body()).doesNotContain("credencialQr");
        assertThat(json.readTree(r.body()).get("id").asLong()).isEqualTo(yo.getId());
    }

    @Test
    void elAltaDeUnTrabajadorYaNoDevuelveLaCredencial() throws Exception {
        Usuario nuevo = usuarioRepository.save(Usuario.builder()
                .nombre("nuevo-" + s).email("nuevo-" + s + "@test.cl").rol(RolUsuario.TRABAJADOR).empresa(empresa).build());

        HttpResponse<String> r = llamar("POST", "/api/trabajadores", token(RolUsuario.ADMIN, "admin", empresa),
                "{\"usuarioId\": %d, \"cuadrillaId\": %d}".formatted(nuevo.getId(), cuadrilla.getId()));

        assertThat(r.statusCode()).isEqualTo(201);
        assertThat(r.body()).doesNotContain("credencialQr");
        assertThat(trabajadorRepository.findByUsuarioId(nuevo.getId()).orElseThrow().getCredencialQr())
                .as("se emite igual, internamente").isNotBlank();
    }

    // ---- no se confunde con el código de un pedido ----------------------

    @Test
    void unCodigoDePedidoNoSeConfundeConUnoDeCredencial() throws Exception {
        String codigoDePedido = "PEDIDO:" + UUID.randomUUID();
        String codigoDeCredencial = codigoNuevo(tokenYo);

        // Escaneado en la ruta de credenciales, el de pedido es un desconocido...
        assertThat(escanear(codigoDePedido, tokenBodeguero).statusCode()).isEqualTo(404);
        assertThat(escanear(codigoDePedido.substring("PEDIDO:".length()), tokenBodeguero).statusCode()).isEqualTo(404);
        // ...y el de credencial no abre un pedido.
        assertThat(llamar("GET", "/api/pedidos-herramientas/qr/" + codigoDeCredencial, tokenBodeguero).statusCode())
                .isEqualTo(404);
    }

    // ---------------------------------------------------------------------

    private String codigoNuevo(String token) throws Exception {
        HttpResponse<String> r = pedirCodigo(token);
        assertThat(r.statusCode()).as(r.body()).isEqualTo(200);
        return json.readTree(r.body()).get("codigo").asString();
    }

    private HttpResponse<String> pedirCodigo(String token) throws Exception {
        return llamar("POST", "/api/trabajadores/yo/credencial/codigo", token);
    }

    private HttpResponse<String> escanear(String codigo, String token) throws Exception {
        return llamar("GET", "/api/trabajadores/por-credencial/" + codigo.replace(" ", "%20"), token);
    }

    private HttpResponse<String> llamar(String metodo, String ruta, String token) throws Exception {
        return llamar(metodo, ruta, token, null);
    }

    private HttpResponse<String> llamar(String metodo, String ruta, String token, String cuerpo) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta));
        if (token != null) {
            b.header("Authorization", "Bearer " + token);
        }
        if (cuerpo != null) {
            b.header("Content-Type", "application/json");
        }
        b.method(metodo, cuerpo == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(cuerpo));
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }

    private Trabajador trabajador(String nombre, Empresa deLaEmpresa) {
        Usuario u = usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(RolUsuario.TRABAJADOR).empresa(deLaEmpresa).build());
        return trabajadorRepository.save(Trabajador.builder()
                .usuario(u).cuadrilla(deLaEmpresa == empresa ? cuadrilla : null)
                .credencialQr("QR-" + UUID.randomUUID()).build());
    }

    private String token(RolUsuario rol, String nombre, Empresa deLaEmpresa) {
        return jwtService.emitir(usuarioRepository.save(Usuario.builder()
                .nombre(nombre + "-" + s).email(nombre + "-" + UUID.randomUUID() + "@test.cl")
                .rol(rol).empresa(deLaEmpresa).build()));
    }
}
