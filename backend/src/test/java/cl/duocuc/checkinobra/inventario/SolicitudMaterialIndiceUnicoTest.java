package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialRepository;
import cl.duocuc.checkinobra.obra.Cuadrilla;
import cl.duocuc.checkinobra.obra.CuadrillaRepository;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraRepository;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.obra.TrabajadorRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.LocalDateTime;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doReturn;

/**
 * Mejora #153: el control de duplicados del #76 vive en la aplicación ({@code existsBy…} más el
 * bloqueo del trabajador). Una base de datos sola no lo hacía cumplir: una escritura que se salte
 * el servicio (un script, un import, otra versión de la API) dejaba dos solicitudes pendientes
 * idénticas. El índice único parcial es la segunda capa, y esta prueba lo comprueba contra la base
 * real, igual que el resto de la suite.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SolicitudMaterialIndiceUnicoTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private JwtService jwtService;

    /** Espía: solo para saltarse el control de la aplicación en una prueba concreta. */
    @MockitoSpyBean private SolicitudMaterialRepository solicitudMaterialRepository;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private Empresa empresa;
    private Obra obra;
    private Trabajador yo;
    private Material volcanita;
    private String tokenYo;

    @BeforeEach
    void prepararCuadrilla() {
        String s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        obra = obraRepository.save(Obra.builder()
                .nombre("Edificio " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
        Cuadrilla cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        Usuario usuario = usuarioRepository.save(Usuario.builder()
                .nombre("maestro-" + s).email("maestro-" + s + "@test.cl")
                .rol(RolUsuario.TRABAJADOR).empresa(empresa).build());
        yo = trabajadorRepository.save(Trabajador.builder()
                .usuario(usuario).cuadrilla(cuadrilla).credencialQr("QR-" + s).build());
        volcanita = materialRepository.save(Material.builder()
                .sku("VOL-" + s).nombre("Volcanita " + s).categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(100).stockMinimo(0).empresa(empresa).build());
        tokenYo = jwtService.emitir(usuario);
    }

    @Test
    void laBaseRechazaDosPendientesIdenticasAunqueSeSalteElServicio() {
        solicitudMaterialRepository.saveAndFlush(solicitud(EstadoSolicitud.PENDIENTE));

        assertThatThrownBy(() -> solicitudMaterialRepository.saveAndFlush(solicitud(EstadoSolicitud.PENDIENTE)))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining(SolicitudMaterial.INDICE_PENDIENTE_UNICA);
    }

    @Test
    void elIndiceSoloCuentaLasPendientes() {
        solicitudMaterialRepository.saveAndFlush(solicitud(EstadoSolicitud.APROBADA));
        solicitudMaterialRepository.saveAndFlush(solicitud(EstadoSolicitud.APROBADA));
        solicitudMaterialRepository.saveAndFlush(solicitud(EstadoSolicitud.RECHAZADA));
        solicitudMaterialRepository.saveAndFlush(solicitud(EstadoSolicitud.CANCELADA));

        assertThatCode(() -> solicitudMaterialRepository.saveAndFlush(solicitud(EstadoSolicitud.PENDIENTE)))
                .doesNotThrowAnyException();
    }

    @Test
    void unaViolacionDelIndiceSigueSiendo409SolicitudDuplicada() throws Exception {
        solicitudMaterialRepository.saveAndFlush(solicitud(EstadoSolicitud.PENDIENTE));
        // El control de la aplicación no ve la pendiente (como en una carrera que lo pase de largo):
        // lo que la frena ahora es el índice, y el trabajador debe recibir lo mismo que antes.
        doReturn(false).when(solicitudMaterialRepository).existsByTrabajadorIdAndMaterialIdAndObraIdAndEstado(
                eq(yo.getId()), eq(volcanita.getId()), eq(obra.getId()), eq(EstadoSolicitud.PENDIENTE));

        HttpResponse<String> respuesta = pedir();

        assertThat(respuesta.statusCode()).isEqualTo(409);
        JsonNode cuerpo = json.readTree(respuesta.body());
        assertThat(cuerpo.get("codigo").asString()).isEqualTo("SOLICITUD_DUPLICADA");
        // El mismo mensaje del control de la aplicación: dice qué material es.
        assertThat(cuerpo.get("mensaje").asString()).contains(volcanita.getNombre());
        assertThat(solicitudMaterialRepository.findByTrabajadorId(yo.getId())).hasSize(1);
    }

    // ---------------------------------------------------------------------

    private SolicitudMaterial solicitud(EstadoSolicitud estado) {
        return SolicitudMaterial.builder()
                .trabajador(yo).material(volcanita).obra(obra)
                .cantidad(5).descripcion("Para el tabique del piso 2")
                .estado(estado).fechaSolicitud(LocalDateTime.now()).build();
    }

    private HttpResponse<String> pedir() throws Exception {
        String cuerpo = "{\"materialId\": %d, \"cantidad\": 5, \"descripcion\": \"Para el tabique del piso 2\"}"
                .formatted(volcanita.getId());
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/solicitudes-material"))
                .header("Authorization", "Bearer " + tokenYo).header("Content-Type", "application/json")
                .header("Idempotency-Key", UUID.randomUUID().toString())
                .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
    }
}
