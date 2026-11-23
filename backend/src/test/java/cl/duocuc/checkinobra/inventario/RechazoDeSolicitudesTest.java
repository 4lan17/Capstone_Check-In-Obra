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
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
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
 * B13 (#33): el bodeguero rechaza una solicitud y tiene que decir por qué. Es el mismo flujo para
 * material y para herramienta, así que cada caso corre contra las dos. Por HTTP, Postgres real.
 *
 * <ul>
 *   <li>Rechazar con motivo: 200, y el trabajador lo ve en su lista (E7).
 *   <li>Sin motivo, o solo espacios: 400, y la solicitud sigue pendiente.
 *   <li>Una solicitud ya resuelta no se rechaza: 409 YA_RESUELTA (RN-07).
 *   <li>Rechazar no mueve nada: ni kardex, ni préstamo, ni estado de la herramienta.
 * </ul>
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class RechazoDeSolicitudesTest {

    private static final String MOTIVO = "No hay stock hasta el jueves";

    /** Qué se solicita: cambia la ruta y lo que se pide, no el flujo. */
    enum Tipo {
        MATERIAL("/api/solicitudes-material"),
        HERRAMIENTA("/api/solicitudes-herramienta");

        final String ruta;

        Tipo(String ruta) {
            this.ruta = ruta;
        }
    }

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private HerramientaRepository herramientaRepository;
    @Autowired private SolicitudMaterialRepository solicitudMaterialRepository;
    @Autowired private SolicitudHerramientaRepository solicitudHerramientaRepository;
    @Autowired private KardexMovimientoRepository kardexMovimientoRepository;
    @Autowired private PrestamoHerramientaRepository prestamoHerramientaRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Obra obra;
    private Cuadrilla cuadrilla;
    private Trabajador yo;
    private String tokenYo;
    private String tokenBodeguero;
    private String tokenAdmin;

    @BeforeEach
    void prepararCuadrilla() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        obra = obraRepository.save(Obra.builder()
                .nombre("Edificio " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
        cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        yo = trabajador("maestro-" + s);
        tokenYo = jwtService.emitir(yo.getUsuario());
        tokenBodeguero = jwtService.emitir(usuario("bodega-" + s, RolUsuario.BODEGUERO, empresa));
        tokenAdmin = jwtService.emitir(usuario("admin-" + s, RolUsuario.ADMIN, empresa));
    }

    // ---- rechazar con motivo ---------------------------------------------

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void rechazarConMotivoEs200YLaSolicitudQuedaRechazadaConSuMotivo(Tipo tipo) throws Exception {
        long id = pedir(tipo);

        HttpResponse<String> r = rechazar(tipo, id, MOTIVO, tokenBodeguero);

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode cuerpo = json.readTree(r.body());
        assertThat(cuerpo.get("estado").asString()).isEqualTo("RECHAZADA");
        assertThat(cuerpo.get("motivoRechazo").asString()).isEqualTo(MOTIVO);
        assertThat(cuerpo.get("resueltoPorId").isNull()).isFalse();
    }

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void elTrabajadorVeElMotivoEnSuListaYEnElDetalle(Tipo tipo) throws Exception {
        long id = pedir(tipo);
        rechazar(tipo, id, MOTIVO, tokenBodeguero);

        JsonNode enMisSolicitudes = null;
        for (JsonNode f : json.readTree(get(tipo.ruta + "/mias", tokenYo).body())) {
            if (f.get("id").asLong() == id) {
                enMisSolicitudes = f;
            }
        }
        assertThat(enMisSolicitudes).as("la solicitud en /mias").isNotNull();
        assertThat(enMisSolicitudes.get("estado").asString()).isEqualTo("RECHAZADA");
        assertThat(enMisSolicitudes.get("motivoRechazo").asString()).isEqualTo(MOTIVO);

        HttpResponse<String> detalle = get(tipo.ruta + "/" + id, tokenYo);
        assertThat(detalle.statusCode()).isEqualTo(200);
        assertThat(json.readTree(detalle.body()).get("motivoRechazo").asString()).isEqualTo(MOTIVO);
    }

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void tambienPuedeRechazarUnAdmin(Tipo tipo) throws Exception {
        long id = pedir(tipo);

        assertThat(rechazar(tipo, id, MOTIVO, tokenAdmin).statusCode()).isEqualTo(200);
    }

    // ---- sin motivo ------------------------------------------------------

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void sinMotivoEsUn400YLaSolicitudSigueEsperando(Tipo tipo) throws Exception {
        long id = pedir(tipo);

        for (String cuerpo : new String[] {"{}", "{\"motivo\": null}", "{\"motivo\": \"\"}",
                "{\"motivo\": \"   \"}", "{\"motivo\": \"\\t \\n\"}"}) {
            HttpResponse<String> r = put(tipo.ruta + "/" + id + "/rechazar", cuerpo, tokenBodeguero);
            assertThat(r.statusCode()).as(cuerpo).isEqualTo(400);
        }
        assertThat(estadoDe(tipo, id)).isEqualTo(EstadoSolicitud.PENDIENTE);
    }

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void unMotivoDemasiadoLargoEsUn400(Tipo tipo) throws Exception {
        long id = pedir(tipo);

        assertThat(rechazar(tipo, id, "x".repeat(501), tokenBodeguero).statusCode()).isEqualTo(400);
        assertThat(estadoDe(tipo, id)).isEqualTo(EstadoSolicitud.PENDIENTE);
    }

    // ---- ya resuelta (RN-07) ---------------------------------------------

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void unaSolicitudYaResueltaNoSePuedeRechazar_409YaResuelta(Tipo tipo) throws Exception {
        for (EstadoSolicitud resuelta : new EstadoSolicitud[] {
                EstadoSolicitud.APROBADA, EstadoSolicitud.ENTREGADA,
                EstadoSolicitud.RECHAZADA, EstadoSolicitud.CANCELADA}) {
            long id = pedirYForzarEstado(tipo, resuelta);

            HttpResponse<String> r = rechazar(tipo, id, MOTIVO, tokenBodeguero);

            assertThat(r.statusCode()).as(resuelta.name()).isEqualTo(409);
            JsonNode cuerpo = json.readTree(r.body());
            assertThat(cuerpo.get("codigo").asString()).as(resuelta.name()).isEqualTo("YA_RESUELTA");
            assertThat(cuerpo.get("mensaje").asString()).contains(resuelta.name().toLowerCase());
            assertThat(estadoDe(tipo, id)).as("no cambia").isEqualTo(resuelta);
        }
    }

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void rechazarDosVecesDejaElPrimerMotivo(Tipo tipo) throws Exception {
        long id = pedir(tipo);
        assertThat(rechazar(tipo, id, MOTIVO, tokenBodeguero).statusCode()).isEqualTo(200);

        HttpResponse<String> segunda = rechazar(tipo, id, "Otro motivo", tokenBodeguero);

        assertThat(segunda.statusCode()).isEqualTo(409);
        assertThat(json.readTree(get(tipo.ruta + "/" + id, tokenYo).body()).get("motivoRechazo").asString())
                .isEqualTo(MOTIVO);
    }

    // ---- no mueve nada ---------------------------------------------------

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void rechazarNoGeneraMovimientoNiPrestamoYNoToca_elEstadoDeLoPedido(Tipo tipo) throws Exception {
        Material material = material("VOL-" + s);
        Herramienta herramienta = herramienta("HER-" + s);
        long id = tipo == Tipo.MATERIAL ? pedirMaterial(material) : pedirHerramienta(herramienta);
        long movimientosAntes = kardexMovimientoRepository.findByObraId(obra.getId()).size();
        long prestamosAntes = prestamoHerramientaRepository.findByObraId(obra.getId()).size();

        assertThat(rechazar(tipo, id, MOTIVO, tokenBodeguero).statusCode()).isEqualTo(200);

        assertThat(kardexMovimientoRepository.findByObraId(obra.getId())).hasSize((int) movimientosAntes);
        assertThat(prestamoHerramientaRepository.findByObraId(obra.getId())).hasSize((int) prestamosAntes);
        assertThat(herramientaRepository.findById(herramienta.getId()).orElseThrow().getEstado())
                .isEqualTo(EstadoHerramienta.DISPONIBLE);
    }

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void unaSolicitudRechazadaSePuedeVolverAPedir(Tipo tipo) throws Exception {
        Material material = material("VOL-" + s);
        Herramienta herramienta = herramienta("HER-" + s);
        long id = tipo == Tipo.MATERIAL ? pedirMaterial(material) : pedirHerramienta(herramienta);
        rechazar(tipo, id, MOTIVO, tokenBodeguero);

        long nueva = tipo == Tipo.MATERIAL ? pedirMaterial(material) : pedirHerramienta(herramienta);

        assertThat(nueva).isNotEqualTo(id);
        assertThat(estadoDe(tipo, nueva)).isEqualTo(EstadoSolicitud.PENDIENTE);
    }

    // ---- quién puede ----------------------------------------------------

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void unTrabajadorNoPuedeRechazar(Tipo tipo) throws Exception {
        long id = pedir(tipo);

        assertThat(rechazar(tipo, id, MOTIVO, tokenYo).statusCode()).isEqualTo(403);
        assertThat(estadoDe(tipo, id)).isEqualTo(EstadoSolicitud.PENDIENTE);
    }

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void elBodegueroDeOtraEmpresaNoEncuentraLaSolicitud_404(Tipo tipo) throws Exception {
        long id = pedir(tipo);
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        String tokenAjeno = jwtService.emitir(usuario("bodega-b-" + s, RolUsuario.BODEGUERO, otra));

        assertThat(rechazar(tipo, id, MOTIVO, tokenAjeno).statusCode()).isEqualTo(404);
        assertThat(estadoDe(tipo, id)).isEqualTo(EstadoSolicitud.PENDIENTE);
    }

    @ParameterizedTest
    @EnumSource(Tipo.class)
    void unaSolicitudQueNoExisteEs404(Tipo tipo) throws Exception {
        assertThat(rechazar(tipo, 999_999_999L, MOTIVO, tokenBodeguero).statusCode()).isEqualTo(404);
    }

    // ---------------------------------------------------------------------

    private long pedir(Tipo tipo) throws Exception {
        return tipo == Tipo.MATERIAL ? pedirMaterial(material("VOL-" + s)) : pedirHerramienta(herramienta("HER-" + s));
    }

    private long pedirMaterial(Material m) throws Exception {
        return crear(Tipo.MATERIAL, "{\"materialId\": %d, \"cantidad\": 5, \"descripcion\": \"Para el tabique del piso 2\"}"
                .formatted(m.getId()));
    }

    private long pedirHerramienta(Herramienta h) throws Exception {
        return crear(Tipo.HERRAMIENTA, "{\"herramientaId\": %d, \"descripcion\": \"Para cortar el tabique del piso 2\"}"
                .formatted(h.getId()));
    }

    private long crear(Tipo tipo, String cuerpo) throws Exception {
        HttpResponse<String> r = http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + tipo.ruta))
                .header("Authorization", "Bearer " + tokenYo).header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
        assertThat(r.statusCode()).as(r.body()).isEqualTo(201);
        return json.readTree(r.body()).get("id").asLong();
    }

    /** Una solicitud nueva y, para no repetir el flujo de despacho que no es lo que se prueba, el estado fijado. */
    private long pedirYForzarEstado(Tipo tipo, EstadoSolicitud estado) throws Exception {
        // Un material/herramienta nuevo por pedido: una pendiente igual bloquearía la siguiente.
        long id = pedir(tipo);
        if (tipo == Tipo.MATERIAL) {
            SolicitudMaterial x = solicitudMaterialRepository.findById(id).orElseThrow();
            x.setEstado(estado);
            solicitudMaterialRepository.save(x);
        } else {
            SolicitudHerramienta x = solicitudHerramientaRepository.findById(id).orElseThrow();
            x.setEstado(estado);
            solicitudHerramientaRepository.save(x);
        }
        return id;
    }

    private EstadoSolicitud estadoDe(Tipo tipo, long id) {
        return tipo == Tipo.MATERIAL
                ? solicitudMaterialRepository.findById(id).orElseThrow().getEstado()
                : solicitudHerramientaRepository.findById(id).orElseThrow().getEstado();
    }

    private HttpResponse<String> rechazar(Tipo tipo, long id, String motivo, String token) throws Exception {
        String cuerpo = "{\"motivo\": \"%s\"}".formatted(motivo);
        return put(tipo.ruta + "/" + id + "/rechazar", cuerpo, token);
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

    private Usuario usuario(String nombre, RolUsuario rol, Empresa deLaEmpresa) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(deLaEmpresa).build());
    }

    private Trabajador trabajador(String nombre) {
        return trabajadorRepository.save(Trabajador.builder()
                .usuario(usuario(nombre, RolUsuario.TRABAJADOR, empresa)).cuadrilla(cuadrilla)
                .credencialQr("QR-" + nombre).build());
    }

    private Material material(String sku) {
        return materialRepository.save(Material.builder()
                .sku(sku + "-" + UUID.randomUUID().toString().substring(0, 4)).nombre("Material " + sku)
                .categoria(CategoriaMaterial.VOLCANITA).precioUnitario(100).stockMinimo(0).empresa(empresa).build());
    }

    private Herramienta herramienta(String codigo) {
        return herramientaRepository.save(Herramienta.builder()
                .codigoQr(codigo + "-" + UUID.randomUUID().toString().substring(0, 4)).nombre("Taladro " + codigo)
                .categoria("Electrica").estado(EstadoHerramienta.DISPONIBLE).valorReposicion(50_000).empresa(empresa)
                .build());
    }
}
