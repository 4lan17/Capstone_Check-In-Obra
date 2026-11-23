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
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG13 (#101, S-30): IdempotenciaFilter guarda en la base la respuesta de cada escritura que trae
 * {@code Idempotency-Key}, para repetírsela al reintento. Eso es un problema si la respuesta lleva
 * una credencial: quedaría en claro en la tabla de claves, y un reintento la volvería a entregar.
 * Los endpoints de credenciales no guardan su respuesta.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class CredencialesSinRespuestaGuardadaTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private JwtService jwtService;
    @Autowired private JdbcTemplate jdbc;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Obra obra;
    private Trabajador yo;
    private String tokenYo;
    private String tokenAdmin;

    @BeforeEach
    void preparar() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        obra = obraRepository.save(Obra.builder()
                .nombre("Edificio " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
        Cuadrilla cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        Usuario u = usuario("maestro-" + s, RolUsuario.TRABAJADOR);
        yo = trabajadorRepository.save(Trabajador.builder().usuario(u).cuadrilla(cuadrilla)
                .credencialQr("QR-" + s).build());
        tokenYo = jwtService.emitir(u);
        tokenAdmin = jwtService.emitir(usuario("admin-" + s, RolUsuario.ADMIN));
    }

    @Test
    void elCodigoDeCredencialSeEmiteDeNuevoEnCadaReintentoYNoQuedaGuardado() throws Exception {
        String clave = UUID.randomUUID().toString();

        HttpResponse<String> primera = enviar("POST", "/api/trabajadores/yo/credencial/codigo", tokenYo, clave, null);
        HttpResponse<String> reintento = enviar("POST", "/api/trabajadores/yo/credencial/codigo", tokenYo, clave, null);

        assertThat(primera.statusCode()).isEqualTo(200);
        assertThat(reintento.statusCode()).isEqualTo(200);
        assertThat(reintento.headers().firstValue("Idempotency-Replayed")).as("no se repite la respuesta").isEmpty();
        assertThat(json.readTree(reintento.body()).get("codigo").asString())
                .isNotEqualTo(json.readTree(primera.body()).get("codigo").asString());
        assertThat(guardadas(clave)).as("la tabla de claves no guarda nada").isZero();
    }

    @Test
    void renovarLaCredencialNoGuardaLaRespuesta() throws Exception {
        String clave = UUID.randomUUID().toString();

        HttpResponse<String> r = enviar("PUT", "/api/trabajadores/yo/credencial", tokenYo, clave, null);

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(guardadas(clave)).isZero();
    }

    @Test
    void elAltaDeUnTrabajadorNoGuardaLaRespuesta() throws Exception {
        Usuario nuevo = usuario("nuevo-" + s, RolUsuario.TRABAJADOR);
        String clave = UUID.randomUUID().toString();

        HttpResponse<String> r = enviar("POST", "/api/trabajadores", tokenAdmin, clave,
                "{\"usuarioId\": %d}".formatted(nuevo.getId()));

        assertThat(r.statusCode()).isEqualTo(201);
        assertThat(guardadas(clave)).isZero();
    }

    @Test
    void laRenovacionDelAdminTampocoGuardaLaRespuesta() throws Exception {
        String clave = UUID.randomUUID().toString();

        HttpResponse<String> r = enviar("PUT", "/api/trabajadores/" + yo.getId() + "/credencial", tokenAdmin, clave, null);

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(guardadas(clave)).isZero();
    }

    @Test
    void unaEscrituraComunSiguesiendoIdempotente() throws Exception {
        // Contraprueba: la exclusión es solo de las rutas de credenciales, no de todo.
        String clave = UUID.randomUUID().toString();
        String cuerpo = "{\"nombre\": \"Cuadrilla %s\", \"obraId\": %d}".formatted(s, obra.getId());

        HttpResponse<String> primera = enviar("POST", "/api/cuadrillas", tokenAdmin, clave, cuerpo);
        HttpResponse<String> reintento = enviar("POST", "/api/cuadrillas", tokenAdmin, clave, cuerpo);

        assertThat(primera.statusCode()).isEqualTo(201);
        assertThat(reintento.headers().firstValue("Idempotency-Replayed")).contains("true");
        assertThat(guardadas(clave)).isEqualTo(1);
    }

    // ---------------------------------------------------------------------

    private long guardadas(String clave) {
        Long n = jdbc.queryForObject(
                "SELECT count(*) FROM claves_idempotencia WHERE clave = CAST(? AS UUID)", Long.class, clave);
        return n == null ? 0 : n;
    }

    private HttpResponse<String> enviar(String metodo, String ruta, String token, String clave, String cuerpo)
            throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).header("Idempotency-Key", clave);
        if (cuerpo != null) {
            b.header("Content-Type", "application/json");
        }
        b.method(metodo, cuerpo == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(cuerpo));
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }

    private Usuario usuario(String nombre, RolUsuario rol) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build());
    }
}
