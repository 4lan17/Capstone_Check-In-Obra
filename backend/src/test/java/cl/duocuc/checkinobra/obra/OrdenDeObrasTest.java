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
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * GET /api/obras sale ordenado por nombre (y por id si hay dos con el mismo nombre). Sin ORDER BY,
 * Postgres devuelve las filas en el orden en que están en disco, y un UPDATE deja la versión nueva de la
 * fila al final: al fijar la ubicación de «Torre B» la app la veía pasar al último lugar de la lista.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrdenDeObrasTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private String tokenAdmin;

    @BeforeEach
    void preparar() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        tokenAdmin = jwtService.emitir(usuarioRepository.save(Usuario.builder()
                .nombre("admin-" + s).email("admin-" + s + "@test.cl").rol(RolUsuario.ADMIN).empresa(empresa).build()));
    }

    @Test
    void salenPorNombreAunqueSeHayanCreadoEnOtroOrden() throws Exception {
        obra("Torre C");
        obra("Torre A");
        obra("Torre B");

        assertThat(nombres()).containsExactly("Torre A", "Torre B", "Torre C");
    }

    @Test
    void actualizarUnaObraNoCambiaSuPosicion() throws Exception {
        Obra a = obra("Torre A");
        Obra b = obra("Torre B");
        Obra c = obra("Torre C");
        List<String> antes = nombres();

        assertThat(ubicar(b)).isEqualTo(200);
        assertThat(nombres()).as("después de fijar la ubicación de B").isEqualTo(antes);
        assertThat(ubicar(a)).isEqualTo(200);
        assertThat(ubicar(b)).isEqualTo(200);
        assertThat(ubicar(c)).isEqualTo(200);
        assertThat(nombres()).as("después de actualizar todas, varias veces").isEqualTo(antes);
        assertThat(antes).containsExactly("Torre A", "Torre B", "Torre C");
    }

    @Test
    void conElMismoNombreDesempataElId() throws Exception {
        Obra primera = obra("Torre igual");
        Obra segunda = obra("Torre igual");
        ubicar(primera); // la primera se actualiza y, sin orden, quedaría después de la segunda

        List<Long> ids = new ArrayList<>();
        for (JsonNode o : listar()) {
            ids.add(o.get("id").asLong());
        }
        assertThat(ids).containsExactly(primera.getId(), segunda.getId());
    }

    @Test
    void elListadoSoloTraeLasObrasDeLaEmpresa() throws Exception {
        obra("Torre A");
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        obraRepository.save(Obra.builder().nombre("Torre Z").cliente("C").ubicacion("U")
                .estado(EstadoObra.ACTIVA).empresa(otra).build());

        assertThat(nombres()).containsExactly("Torre A");
    }

    // ---------------------------------------------------------------------

    private Obra obra(String nombre) {
        return obraRepository.save(Obra.builder().nombre(nombre).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
    }

    private int ubicar(Obra obra) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/obras/" + obra.getId() + "/ubicacion"))
                        .header("Authorization", "Bearer " + tokenAdmin).header("Content-Type", "application/json")
                        .PUT(HttpRequest.BodyPublishers.ofString("{\"latitud\": -33.45, \"longitud\": -70.66}")).build(),
                HttpResponse.BodyHandlers.ofString()).statusCode();
    }

    private JsonNode listar() throws Exception {
        HttpResponse<String> r = http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/obras"))
                .header("Authorization", "Bearer " + tokenAdmin).GET().build(), HttpResponse.BodyHandlers.ofString());
        assertThat(r.statusCode()).isEqualTo(200);
        return json.readTree(r.body());
    }

    private List<String> nombres() throws Exception {
        List<String> nombres = new ArrayList<>();
        for (JsonNode o : listar()) {
            nombres.add(o.get("nombre").asString());
        }
        return nombres;
    }
}
