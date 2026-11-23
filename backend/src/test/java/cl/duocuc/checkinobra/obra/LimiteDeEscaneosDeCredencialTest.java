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
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG13 (#101): el código de credencial es corto (8 caracteres) y se canjea por HTTP, así que quien
 * escanea no puede probar códigos sin límite. Los escaneos que no reconocen el código se cuentan por
 * quien escanea y, pasado el tope, bloquean con 429, igual que el login ({@code LimitadorDeIntentos}).
 * Un código vencido no cuenta: ahí el código era real.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {"checkinobra.credencial.escaneo.max-fallos=5"})
class LimiteDeEscaneosDeCredencialTest {

    private static final int MAX_FALLOS = 5;

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private CodigoCredencialRepository codigoCredencialRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Trabajador yo;
    private String tokenBodeguero;

    @BeforeEach
    void preparar() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        Usuario u = usuario("maestro-" + s, RolUsuario.TRABAJADOR);
        yo = trabajadorRepository.save(Trabajador.builder().usuario(u).credencialQr("QR-" + s).build());
        tokenBodeguero = jwtService.emitir(usuario("bodega-" + s, RolUsuario.BODEGUERO));
    }

    @Test
    void pasadoElTopeDeCodigosDesconocidosElEscaneoSeBloqueaConUn429() throws Exception {
        for (int i = 0; i < MAX_FALLOS; i++) {
            assertThat(escanear("ZZZZ999" + (i + 2), tokenBodeguero).statusCode()).as("intento %d", i + 1).isEqualTo(404);
        }

        HttpResponse<String> bloqueado = escanear("ZZZZ9999", tokenBodeguero);

        assertThat(bloqueado.statusCode()).isEqualTo(429);
        assertThat(bloqueado.headers().firstValue("Retry-After")).isPresent();
        assertThat(json.readTree(bloqueado.body()).get("codigo").asString()).isEqualTo("DEMASIADOS_INTENTOS");
    }

    @Test
    void elBloqueoEsDeQuienEscaneaYNoDeTodaLaEmpresa() throws Exception {
        for (int i = 0; i <= MAX_FALLOS; i++) {
            escanear("ZZZZ999" + (i + 2), tokenBodeguero);
        }
        String otroBodeguero = jwtService.emitir(usuario("bodega-2-" + s, RolUsuario.BODEGUERO));

        assertThat(escanear("ZZZZ9999", tokenBodeguero).statusCode()).isEqualTo(429);
        assertThat(escanear("ZZZZ9999", otroBodeguero).statusCode()).isEqualTo(404);
    }

    @Test
    void unCodigoVencidoNoCuentaComoIntento() throws Exception {
        String vencido = CodigosDePrueba.unico();
        codigoCredencialRepository.save(CodigoCredencial.builder().codigo(vencido).trabajador(yo)
                .creadoEn(Instant.now().minusSeconds(300)).expiraEn(Instant.now().minusSeconds(60)).build());

        for (int i = 0; i < MAX_FALLOS * 3; i++) {
            assertThat(escanear(vencido, tokenBodeguero).statusCode()).isEqualTo(409);
        }
    }

    @Test
    void unEscaneoQueAciertaBorraLaCuenta() throws Exception {
        String bueno = CodigosDePrueba.unico();
        codigoCredencialRepository.save(CodigoCredencial.builder().codigo(bueno).trabajador(yo)
                .creadoEn(Instant.now()).expiraEn(Instant.now().plusSeconds(120)).build());

        for (int ronda = 0; ronda < 3; ronda++) {
            for (int i = 0; i < MAX_FALLOS - 1; i++) {
                assertThat(escanear("ZZZZ999" + (i + 2), tokenBodeguero).statusCode()).isEqualTo(404);
            }
            assertThat(escanear(bueno, tokenBodeguero).statusCode()).as("ronda %d", ronda).isEqualTo(200);
        }
    }

    // ---------------------------------------------------------------------

    private HttpResponse<String> escanear(String codigo, String token) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create(
                        "http://localhost:" + puerto + "/api/trabajadores/por-credencial/" + codigo))
                .header("Authorization", "Bearer " + token).GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    private Usuario usuario(String nombre, RolUsuario rol) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build());
    }
}
