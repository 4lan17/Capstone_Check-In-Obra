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
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * GET /api/materiales y GET /api/herramientas salen por nombre (y por id si se llaman igual). Sin ORDER BY
 * Postgres devuelve las filas en el orden en que están en disco, y un UPDATE deja la versión nueva al
 * final: un material saltaba al último lugar al cambiarle el precio, y una herramienta al prestarla o
 * devolverla. Las dos se actualizan todo el tiempo.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrdenDeCatalogosTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private HerramientaRepository herramientaRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private String tokenAdmin;
    private String tokenBodeguero;
    private String tokenTrabajador;
    private Obra obra;
    private Trabajador trabajador;

    @BeforeEach
    void preparar() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        tokenAdmin = jwtService.emitir(usuario("admin", RolUsuario.ADMIN));
        tokenBodeguero = jwtService.emitir(usuario("bodega", RolUsuario.BODEGUERO));
        obra = obraRepository.save(Obra.builder().nombre("Edificio " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
        Cuadrilla cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        Usuario u = usuario("peon", RolUsuario.TRABAJADOR);
        trabajador = trabajadorRepository.save(Trabajador.builder().usuario(u).cuadrilla(cuadrilla)
                .credencialQr("QR-" + s).build());
        tokenTrabajador = jwtService.emitir(u);
    }

    // ---- materiales ------------------------------------------------------

    @Test
    void losMaterialesSalenPorNombreAunqueSeHayanCreadoEnOtroOrden() throws Exception {
        material("Cemento");
        material("Albañilería");
        material("Bisagra");

        assertThat(nombres("/api/materiales", tokenAdmin)).containsExactly("Albañilería", "Bisagra", "Cemento");
    }

    @Test
    void cambiarElPrecioDeUnMaterialNoCambiaSuPosicion() throws Exception {
        List<Material> materiales = List.of(material("Cemento A"), material("Cemento B"), material("Cemento C"));
        List<String> antes = nombres("/api/materiales", tokenAdmin);
        assertThat(antes).containsExactly("Cemento A", "Cemento B", "Cemento C");

        assertThat(cambiarPrecio(materiales.get(1), 1234)).isEqualTo(200);
        assertThat(nombres("/api/materiales", tokenAdmin)).as("después de cambiar el de B").isEqualTo(antes);

        for (Material m : materiales) {
            assertThat(cambiarPrecio(m, 999)).isEqualTo(200);
        }
        assertThat(nombres("/api/materiales", tokenAdmin)).as("después de cambiarlos todos").isEqualTo(antes);
        assertThat(nombres("/api/materiales?categoria=VOLCANITA", tokenAdmin)).as("filtrado por categoría").isEqualTo(antes);
        assertThat(nombres("/api/materiales", tokenTrabajador)).as("visto por un trabajador").isEqualTo(antes);
    }

    @Test
    void conElMismoNombreDesempataElIdTambienEnElFiltroPorCategoria() throws Exception {
        Material primero = material("Tornillo");
        Material segundo = material("Tornillo");
        cambiarPrecio(primero, 50);

        for (String ruta : new String[] {"/api/materiales", "/api/materiales?categoria=VOLCANITA"}) {
            assertThat(ids(ruta, tokenAdmin)).as(ruta).containsExactly(primero.getId(), segundo.getId());
        }
    }

    // ---- herramientas ----------------------------------------------------

    @Test
    void lasHerramientasSalenPorNombreAunqueSeHayanCreadoEnOtroOrden() throws Exception {
        herramienta("Taladro");
        herramienta("Amoladora");
        herramienta("Nivel");

        assertThat(nombres("/api/herramientas", tokenBodeguero)).containsExactly("Amoladora", "Nivel", "Taladro");
    }

    @Test
    void prestarYDevolverUnaHerramientaNoCambiaSuPosicion() throws Exception {
        Herramienta a = herramienta("Herramienta A");
        Herramienta b = herramienta("Herramienta B");
        herramienta("Herramienta C");
        List<String> antes = nombres("/api/herramientas", tokenBodeguero);
        assertThat(antes).containsExactly("Herramienta A", "Herramienta B", "Herramienta C");

        // Un préstamo real: la herramienta pasa a PRESTADA (UPDATE).
        long prestamoId = prestar(b);
        assertThat(nombres("/api/herramientas", tokenBodeguero)).as("prestada B").isEqualTo(antes);
        assertThat(estadoDe(b)).isEqualTo(EstadoHerramienta.PRESTADA);

        // Y al devolverla vuelve a cambiar de estado (otro UPDATE), esta vez a mantención.
        assertThat(devolver(prestamoId, EstadoHerramienta.MANTENCION)).isEqualTo(200);
        assertThat(nombres("/api/herramientas", tokenBodeguero)).as("devuelta B en mantención").isEqualTo(antes);
        assertThat(estadoDe(b)).isEqualTo(EstadoHerramienta.MANTENCION);

        // Con la primera, que es la que más fácil saltaría al final.
        long otro = prestar(a);
        assertThat(nombres("/api/herramientas", tokenBodeguero)).as("prestada A").isEqualTo(antes);
        devolver(otro, EstadoHerramienta.DISPONIBLE);
        assertThat(nombres("/api/herramientas", tokenBodeguero)).as("devuelta A").isEqualTo(antes);
    }

    @Test
    void conElMismoNombreDesempataElIdEnHerramientas() throws Exception {
        Herramienta primera = herramienta("Taladro");
        Herramienta segunda = herramienta("Taladro");
        prestar(primera);

        assertThat(ids("/api/herramientas", tokenBodeguero)).containsExactly(primera.getId(), segunda.getId());
    }

    @Test
    void lasListasSoloTraenLoDeLaEmpresa() throws Exception {
        material("Cemento");
        herramienta("Taladro");
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        materialRepository.save(Material.builder().sku("AJ-" + s).nombre("Ajeno").categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(1).stockMinimo(0).empresa(otra).build());
        herramientaRepository.save(Herramienta.builder().codigoQr("AJ-" + s).nombre("Ajena").categoria("Eléctrica")
                .estado(EstadoHerramienta.DISPONIBLE).valorReposicion(1).empresa(otra).build());

        assertThat(nombres("/api/materiales", tokenAdmin)).containsExactly("Cemento");
        assertThat(nombres("/api/herramientas", tokenBodeguero)).containsExactly("Taladro");
    }

    // ---------------------------------------------------------------------

    private Material material(String nombre) {
        return materialRepository.save(Material.builder()
                // El SKU no tiene relación con el nombre a propósito: hay un índice único por (empresa, sku) y,
                // si coincidieran, la lista saldría "ordenada" por nombre sin que nadie se lo pida.
                .sku(UUID.randomUUID().toString())
                .nombre(nombre).categoria(CategoriaMaterial.VOLCANITA).precioUnitario(100).stockMinimo(0)
                .empresa(empresa).build());
    }

    private Herramienta herramienta(String nombre) {
        return herramientaRepository.save(Herramienta.builder()
                .codigoQr("H-" + UUID.randomUUID()).nombre(nombre).categoria("Eléctrica")
                .estado(EstadoHerramienta.DISPONIBLE).valorReposicion(90000).empresa(empresa).build());
    }

    private EstadoHerramienta estadoDe(Herramienta h) {
        return herramientaRepository.findById(h.getId()).orElseThrow().getEstado();
    }

    private Usuario usuario(String nombre, RolUsuario rol) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre + "-" + s).email(nombre + "-" + UUID.randomUUID() + "@test.cl").rol(rol).empresa(empresa).build());
    }

    private int cambiarPrecio(Material m, double precio) throws Exception {
        return enviar("PUT", "/api/materiales/" + m.getId() + "/precio", tokenAdmin, "{\"nuevoPrecio\": " + precio + "}").statusCode();
    }

    private long prestar(Herramienta h) throws Exception {
        HttpResponse<String> r = enviar("POST", "/api/prestamos-herramienta", tokenBodeguero,
                "{\"herramientaId\": %d, \"trabajadorId\": %d, \"obraId\": %d, \"fechaDevolEsperada\": \"%s\"}"
                        .formatted(h.getId(), trabajador.getId(), obra.getId(), LocalDateTime.now().plusDays(1).withNano(0)));
        assertThat(r.statusCode()).as(r.body()).isEqualTo(201);
        return json.readTree(r.body()).get("id").asLong();
    }

    private int devolver(long prestamoId, EstadoHerramienta nuevoEstado) throws Exception {
        return enviar("PUT", "/api/prestamos-herramienta/" + prestamoId + "/devolucion", tokenBodeguero,
                "{\"nuevoEstadoHerramienta\": \"" + nuevoEstado + "\"}").statusCode();
    }

    private HttpResponse<String> enviar(String metodo, String ruta, String token, String cuerpo) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).header("Content-Type", "application/json")
                .method(metodo, HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
    }

    private JsonNode listar(String ruta, String token) throws Exception {
        HttpResponse<String> r = http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).GET().build(), HttpResponse.BodyHandlers.ofString());
        assertThat(r.statusCode()).as(ruta + " → " + r.body()).isEqualTo(200);
        return json.readTree(r.body());
    }

    private List<String> nombres(String ruta, String token) throws Exception {
        List<String> nombres = new ArrayList<>();
        for (JsonNode f : listar(ruta, token)) {
            nombres.add(f.get("nombre").asString());
        }
        return nombres;
    }

    private List<Long> ids(String ruta, String token) throws Exception {
        List<Long> ids = new ArrayList<>();
        for (JsonNode f : listar(ruta, token)) {
            ids.add(f.get("id").asLong());
        }
        return ids;
    }
}
