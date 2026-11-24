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
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * #204: la obra tiene una ubicación en el mapa (latitud y longitud, opcionales y siempre juntas)
 * además del texto {@code ubicacion}, que no cambia. Por HTTP contra el servidor de verdad y Postgres
 * real; los CHECK de la migración V16 se prueban también directo contra la base.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class UbicacionDeObraTest {

    private static final double LAT_SANTIAGO = -33.448890;
    private static final double LON_SANTIAGO = -70.669265;

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private JwtService jwtService;
    @Autowired private JdbcTemplate jdbc;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private String tokenAdmin;
    private Obra obra;

    @BeforeEach
    void preparar() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        tokenAdmin = token(RolUsuario.ADMIN, "admin", empresa);
        obra = obra("Edificio " + s, empresa);
    }

    // ---- alta ------------------------------------------------------------

    @Test
    void elAltaAceptaLatitudYLongitudYLasDevuelve() throws Exception {
        HttpResponse<String> r = crear(cuerpoDeAlta(LAT_SANTIAGO, LON_SANTIAGO));

        assertThat(r.statusCode()).isEqualTo(201);
        JsonNode j = json.readTree(r.body());
        assertThat(j.get("latitud").asDouble()).isEqualTo(LAT_SANTIAGO);
        assertThat(j.get("longitud").asDouble()).isEqualTo(LON_SANTIAGO);
        assertThat(j.get("ubicacion").asString()).isEqualTo("Av. Providencia 1234");
    }

    @Test
    void elAltaSinCoordenadasSigueFuncionandoYLasDevuelveNulas() throws Exception {
        HttpResponse<String> r = crear(cuerpoDeAlta(null, null));

        assertThat(r.statusCode()).isEqualTo(201);
        JsonNode j = json.readTree(r.body());
        assertThat(j.has("latitud")).as("la clave viene, en null").isTrue();
        assertThat(j.get("latitud").isNull()).isTrue();
        assertThat(j.get("longitud").isNull()).isTrue();
    }

    @Test
    void elAltaConUnaSolaCoordenadaEs400() throws Exception {
        for (String cuerpo : new String[] {cuerpoDeAlta(LAT_SANTIAGO, null), cuerpoDeAlta(null, LON_SANTIAGO)}) {
            HttpResponse<String> r = crear(cuerpo);

            assertThat(r.statusCode()).isEqualTo(400);
            assertThat(json.readTree(r.body()).get("mensaje").asString()).containsIgnoringCase("latitud y longitud");
        }
    }

    @Test
    void elAltaConCoordenadasFueraDeRangoEs400ConUnMensajeClaro() throws Exception {
        double[][] malas = {{90.01, 0}, {-90.01, 0}, {0, 180.01}, {0, -180.01}, {1000, 1000}};
        for (double[] c : malas) {
            HttpResponse<String> r = crear(cuerpoDeAlta(c[0], c[1]));

            assertThat(r.statusCode()).as("%s, %s", c[0], c[1]).isEqualTo(400);
            assertThat(json.readTree(r.body()).get("mensaje").asString()).as("%s, %s", c[0], c[1])
                    .containsAnyOf("entre -90 y 90", "entre -180 y 180");
        }
    }

    @Test
    void losExtremosDelRangoSonValidos() throws Exception {
        double[][] buenas = {{90, 180}, {-90, -180}, {0, 0}};
        for (double[] c : buenas) {
            assertThat(crear(cuerpoDeAlta(c[0], c[1])).statusCode()).as("%s, %s", c[0], c[1]).isEqualTo(201);
        }
    }

    @Test
    void laEmpresaNoSePuedeElegirEnElAlta() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        String cuerpo = "{\"nombre\":\"Obra %s\",\"cliente\":\"C\",\"ubicacion\":\"U\",\"empresaId\":%d}"
                .formatted(s, otra.getId());

        JsonNode j = json.readTree(crear(cuerpo).body());

        assertThat(j.get("empresaId").asLong()).isEqualTo(empresa.getId());
    }

    // ---- PUT /ubicacion --------------------------------------------------

    @Test
    void elAdminFijaLaUbicacionDeUnaObra() throws Exception {
        HttpResponse<String> r = ubicar(obra.getId(), LAT_SANTIAGO, LON_SANTIAGO, tokenAdmin);

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode j = json.readTree(r.body());
        assertThat(j.get("id").asLong()).isEqualTo(obra.getId());
        assertThat(j.get("latitud").asDouble()).isEqualTo(LAT_SANTIAGO);
        assertThat(j.get("longitud").asDouble()).isEqualTo(LON_SANTIAGO);
        Obra guardada = obraRepository.findById(obra.getId()).orElseThrow();
        assertThat(guardada.getLatitud().doubleValue()).isEqualTo(LAT_SANTIAGO);
    }

    @Test
    void sePuedeCambiarLaUbicacionYSeGuardaConSeisDecimales() throws Exception {
        ubicar(obra.getId(), LAT_SANTIAGO, LON_SANTIAGO, tokenAdmin);

        HttpResponse<String> r = ubicar(obra.getId(), -33.4488897, -70.6692651, tokenAdmin);

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode j = json.readTree(r.body());
        assertThat(j.get("latitud").asDouble()).isEqualTo(-33.44889);
        assertThat(j.get("longitud").asDouble()).isEqualTo(-70.669265);
    }

    @Test
    void laUbicacionNoCambiaElTextoNiElResto() throws Exception {
        JsonNode j = json.readTree(ubicar(obra.getId(), LAT_SANTIAGO, LON_SANTIAGO, tokenAdmin).body());

        assertThat(j.get("ubicacion").asString()).isEqualTo(obra.getUbicacion());
        assertThat(j.get("nombre").asString()).isEqualTo(obra.getNombre());
        assertThat(j.get("estado").asString()).isEqualTo("ACTIVA");
    }

    @Test
    void sinUnaDeLasDosCoordenadasEs400YNoSeToca() throws Exception {
        ubicar(obra.getId(), LAT_SANTIAGO, LON_SANTIAGO, tokenAdmin);

        for (String cuerpo : new String[] {"{\"latitud\": -10.5}", "{\"longitud\": -70.5}", "{}",
                "{\"latitud\": null, \"longitud\": null}"}) {
            HttpResponse<String> r = put("/api/obras/" + obra.getId() + "/ubicacion", cuerpo, tokenAdmin);

            assertThat(r.statusCode()).as(cuerpo).isEqualTo(400);
        }
        assertThat(obraRepository.findById(obra.getId()).orElseThrow().getLatitud().doubleValue())
                .isEqualTo(LAT_SANTIAGO);
    }

    @Test
    void fueraDeRangoEs400ConMensajeClaro() throws Exception {
        double[][] malas = {{91, 0}, {-91, 0}, {0, 181}, {0, -181}};
        for (double[] c : malas) {
            HttpResponse<String> r = ubicar(obra.getId(), c[0], c[1], tokenAdmin);

            assertThat(r.statusCode()).as("%s, %s", c[0], c[1]).isEqualTo(400);
            assertThat(json.readTree(r.body()).get("mensaje").asString())
                    .containsAnyOf("entre -90 y 90", "entre -180 y 180");
        }
        assertThat(obraRepository.findById(obra.getId()).orElseThrow().getLatitud()).isNull();
    }

    @Test
    void unaObraCerradaEs409ObraCerrada() throws Exception {
        obra.setEstado(EstadoObra.CERRADA);
        obraRepository.save(obra);

        HttpResponse<String> r = ubicar(obra.getId(), LAT_SANTIAGO, LON_SANTIAGO, tokenAdmin);

        assertThat(r.statusCode()).isEqualTo(409);
        JsonNode j = json.readTree(r.body());
        assertThat(j.get("codigo").asString()).isEqualTo("OBRA_CERRADA");
        assertThat(j.get("mensaje").asString()).contains(obra.getNombre());
        assertThat(obraRepository.findById(obra.getId()).orElseThrow().getLatitud()).isNull();
    }

    @Test
    void soloElAdminPuedeFijarla() throws Exception {
        for (RolUsuario rol : new RolUsuario[] {RolUsuario.JEFE_TERRENO, RolUsuario.BODEGUERO, RolUsuario.TRABAJADOR}) {
            String token = token(rol, rol.name().toLowerCase(), empresa);

            assertThat(ubicar(obra.getId(), LAT_SANTIAGO, LON_SANTIAGO, token).statusCode()).as(rol.name()).isEqualTo(403);
        }
        assertThat(obraRepository.findById(obra.getId()).orElseThrow().getLatitud()).isNull();
    }

    @Test
    void sinTokenNoSeFija() throws Exception {
        HttpResponse<String> r = http.send(HttpRequest.newBuilder(URI.create(
                        "http://localhost:" + puerto + "/api/obras/" + obra.getId() + "/ubicacion"))
                .header("Content-Type", "application/json")
                .PUT(HttpRequest.BodyPublishers.ofString("{\"latitud\":1,\"longitud\":1}")).build(),
                HttpResponse.BodyHandlers.ofString());

        assertThat(r.statusCode()).isIn(401, 403);
    }

    @Test
    void laObraDeOtraEmpresaEs404ComoUnaQueNoExiste() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        String tokenAjeno = token(RolUsuario.ADMIN, "admin-b", otra);

        HttpResponse<String> ajena = ubicar(obra.getId(), LAT_SANTIAGO, LON_SANTIAGO, tokenAjeno);
        HttpResponse<String> inexistente = ubicar(999_999_999L, LAT_SANTIAGO, LON_SANTIAGO, tokenAjeno);

        assertThat(ajena.statusCode()).isEqualTo(404);
        assertThat(inexistente.statusCode()).isEqualTo(404);
        assertThat(obraRepository.findById(obra.getId()).orElseThrow().getLatitud()).isNull();
    }

    // ---- dónde más aparece -----------------------------------------------

    @Test
    void laUbicacionApareceEnLaObraEnElListadoYEnElDetalle() throws Exception {
        ubicar(obra.getId(), LAT_SANTIAGO, LON_SANTIAGO, tokenAdmin);

        JsonNode individual = json.readTree(get("/api/obras/" + obra.getId(), tokenAdmin).body());
        JsonNode detalle = json.readTree(get("/api/obras/" + obra.getId() + "/detalle", tokenAdmin).body());
        JsonNode enLista = null;
        for (JsonNode o : json.readTree(get("/api/obras", tokenAdmin).body())) {
            if (o.get("id").asLong() == obra.getId()) {
                enLista = o;
            }
        }

        assertThat(individual.get("latitud").asDouble()).isEqualTo(LAT_SANTIAGO);
        assertThat(detalle.get("obra").get("latitud").asDouble()).isEqualTo(LAT_SANTIAGO);
        assertThat(detalle.get("obra").get("longitud").asDouble()).isEqualTo(LON_SANTIAGO);
        assertThat(enLista).isNotNull();
        assertThat(enLista.get("longitud").asDouble()).isEqualTo(LON_SANTIAGO);
    }

    @Test
    void unaObraSinUbicacionLaDevuelveNula() throws Exception {
        JsonNode j = json.readTree(get("/api/obras/" + obra.getId(), tokenAdmin).body());

        assertThat(j.get("latitud").isNull()).isTrue();
        assertThat(j.get("longitud").isNull()).isTrue();
    }

    // ---- la base lo hace cumplir también (V16) ---------------------------

    @Test
    void laBaseRechazaUnaSolaCoordenadaYLosRangosAunqueSeSalteLaApi() {
        String sql = "UPDATE obras SET latitud = ?, longitud = ? WHERE id = ?";
        Object[][] invalidas = {{10.0, null}, {null, 10.0}, {90.5, 0.0}, {-90.5, 0.0}, {0.0, 180.5}, {0.0, -180.5}};

        for (Object[] c : invalidas) {
            assertThatThrownBy(() -> jdbc.update(sql, c[0], c[1], obra.getId()))
                    .as("%s, %s", c[0], c[1]).isInstanceOf(DataIntegrityViolationException.class);
        }
        assertThat(jdbc.update(sql, 90.0, 180.0, obra.getId())).isEqualTo(1);
        assertThat(jdbc.update(sql, null, null, obra.getId())).isEqualTo(1);
    }

    // ---------------------------------------------------------------------

    private static String cuerpoDeAlta(Double latitud, Double longitud) {
        StringBuilder b = new StringBuilder(
                "{\"nombre\":\"Obra nueva\",\"cliente\":\"Cliente\",\"ubicacion\":\"Av. Providencia 1234\"");
        if (latitud != null) {
            b.append(",\"latitud\":").append(latitud);
        }
        if (longitud != null) {
            b.append(",\"longitud\":").append(longitud);
        }
        return b.append("}").toString();
    }

    private HttpResponse<String> crear(String cuerpo) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/obras"))
                .header("Authorization", "Bearer " + tokenAdmin).header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> ubicar(Long obraId, double latitud, double longitud, String token) throws Exception {
        return put("/api/obras/" + obraId + "/ubicacion",
                "{\"latitud\": %s, \"longitud\": %s}".formatted(latitud, longitud), token);
    }

    private HttpResponse<String> put(String ruta, String cuerpo, String token) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).header("Content-Type", "application/json")
                .PUT(HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> get(String ruta, String token) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    private Obra obra(String nombre, Empresa deLaEmpresa) {
        return obraRepository.save(Obra.builder()
                .nombre(nombre).cliente("Cliente").ubicacion("Santiago").estado(EstadoObra.ACTIVA).empresa(deLaEmpresa)
                .build());
    }

    private String token(RolUsuario rol, String nombre, Empresa deLaEmpresa) {
        return jwtService.emitir(usuarioRepository.save(Usuario.builder()
                .nombre(nombre + "-" + s).email(nombre + "-" + UUID.randomUUID() + "@test.cl")
                .rol(rol).empresa(deLaEmpresa).build()));
    }
}
