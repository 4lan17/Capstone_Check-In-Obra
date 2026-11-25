package cl.duocuc.checkinobra.metricas;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.control.Alerta;
import cl.duocuc.checkinobra.control.AlertaRepository;
import cl.duocuc.checkinobra.control.TipoAlerta;
import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialRepository;
import cl.duocuc.checkinobra.inventario.EstadoHerramienta;
import cl.duocuc.checkinobra.inventario.Herramienta;
import cl.duocuc.checkinobra.inventario.HerramientaRepository;
import cl.duocuc.checkinobra.inventario.KardexMovimiento;
import cl.duocuc.checkinobra.inventario.KardexMovimientoRepository;
import cl.duocuc.checkinobra.inventario.PrestamoHerramienta;
import cl.duocuc.checkinobra.inventario.PrestamoHerramientaRepository;
import cl.duocuc.checkinobra.inventario.TipoMovimiento;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraRepository;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.obra.TrabajadorRepository;
import cl.duocuc.checkinobra.presupuesto.EstadoPresupuesto;
import cl.duocuc.checkinobra.presupuesto.Presupuesto;
import cl.duocuc.checkinobra.presupuesto.PresupuestoItem;
import cl.duocuc.checkinobra.presupuesto.PresupuestoItemRepository;
import cl.duocuc.checkinobra.presupuesto.PresupuestoRepository;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.UUID;

/**
 * Lo común de las pruebas de métricas (#203): una empresa propia por prueba, con sus usuarios,
 * una obra y las piezas para armar presupuesto, kardex, alertas y préstamos. Por HTTP contra el
 * servidor de verdad y Postgres real. Las fechas se arman respecto de "hoy" en America/Santiago,
 * la zona del periodo.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
abstract class MetricasBase {

    static final ZoneId SANTIAGO = ZoneId.of("America/Santiago");
    static final double PRECIO_VOLCANITA = 5000;
    static final double PRECIO_TORNILLO = 10;
    static final double PRECIO_YESO = 300;

    @LocalServerPort protected int puerto;

    @Autowired protected EmpresaRepository empresaRepository;
    @Autowired protected UsuarioRepository usuarioRepository;
    @Autowired protected ObraRepository obraRepository;
    @Autowired protected MaterialRepository materialRepository;
    @Autowired protected PresupuestoRepository presupuestoRepository;
    @Autowired protected PresupuestoItemRepository presupuestoItemRepository;
    @Autowired protected KardexMovimientoRepository kardexMovimientoRepository;
    @Autowired protected AlertaRepository alertaRepository;
    @Autowired protected HerramientaRepository herramientaRepository;
    @Autowired protected PrestamoHerramientaRepository prestamoHerramientaRepository;
    @Autowired protected TrabajadorRepository trabajadorRepository;
    @Autowired protected JwtService jwtService;

    protected final HttpClient http = HttpClient.newHttpClient();
    protected final JsonMapper json = JsonMapper.builder().build();

    protected String s;
    protected LocalDate hoy;
    protected Empresa empresa;
    protected Usuario jefe;
    protected Obra obra;
    protected Material volcanita;
    protected Material tornillo;
    protected Material yeso;
    protected String tokenAdmin;
    protected String tokenJefe;
    protected String tokenBodeguero;
    protected String tokenTrabajador;

    @BeforeEach
    void prepararLaEmpresa() {
        s = UUID.randomUUID().toString().substring(0, 8);
        hoy = LocalDate.now(SANTIAGO);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        jefe = usuario("jefe", RolUsuario.JEFE_TERRENO, empresa);
        tokenAdmin = token(usuario("admin", RolUsuario.ADMIN, empresa));
        tokenJefe = token(jefe);
        tokenBodeguero = token(usuario("bodega", RolUsuario.BODEGUERO, empresa));
        tokenTrabajador = token(usuario("trab", RolUsuario.TRABAJADOR, empresa));
        obra = obra("Edificio " + s, empresa, jefe, EstadoObra.ACTIVA);
        volcanita = material("VOL-" + s, PRECIO_VOLCANITA, empresa);
        tornillo = material("TOR-" + s, PRECIO_TORNILLO, empresa);
        yeso = material("YES-" + s, PRECIO_YESO, empresa);
    }

    // ---- armado de datos -------------------------------------------------

    protected Usuario usuario(String nombre, RolUsuario rol, Empresa deLaEmpresa) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre + "-" + s).email(nombre + "-" + UUID.randomUUID() + "@test.cl")
                .rol(rol).empresa(deLaEmpresa).build());
    }

    protected String token(Usuario u) {
        return jwtService.emitir(u);
    }

    protected Obra obra(String nombre, Empresa deLaEmpresa, Usuario jefeDeTerreno, EstadoObra estado) {
        return obraRepository.save(Obra.builder()
                .nombre(nombre).cliente("Cliente").ubicacion("Santiago").estado(estado)
                .jefeTerreno(jefeDeTerreno).empresa(deLaEmpresa).build());
    }

    protected Material material(String sku, double precio, Empresa deLaEmpresa) {
        return materialRepository.save(Material.builder()
                .sku(sku).nombre("Material " + sku).categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(precio).stockMinimo(0).empresa(deLaEmpresa).build());
    }

    /** Un presupuesto congelado con estos ítems a su precio de catálogo de hoy. */
    protected Presupuesto presupuesto(Obra deLaObra, Object... materialYCantidad) {
        double total = 0;
        for (int i = 0; i < materialYCantidad.length; i += 2) {
            Material m = (Material) materialYCantidad[i];
            total += (double) materialYCantidad[i + 1] * m.getPrecioUnitario();
        }
        Presupuesto p = presupuestoRepository.save(
                Presupuesto.builder().estado(EstadoPresupuesto.CONGELADO).total(total).obra(deLaObra).build());
        for (int i = 0; i < materialYCantidad.length; i += 2) {
            Material m = (Material) materialYCantidad[i];
            double cantidad = (double) materialYCantidad[i + 1];
            presupuestoItemRepository.save(PresupuestoItem.builder().presupuesto(p).material(m).cantidad(cantidad)
                    .precioUnitario(m.getPrecioUnitario()).subtotal(cantidad * m.getPrecioUnitario()).build());
        }
        return p;
    }

    protected KardexMovimiento movimiento(Obra deLaObra, Material m, TipoMovimiento tipo, double cantidad, LocalDate dia) {
        return movimiento(deLaObra, m, tipo, cantidad, dia.atTime(10, 0));
    }

    protected KardexMovimiento movimiento(Obra deLaObra, Material m, TipoMovimiento tipo, double cantidad, LocalDateTime fecha) {
        return kardexMovimientoRepository.save(KardexMovimiento.builder()
                .tipoMovimiento(tipo).cantidad(cantidad).fecha(fecha)
                .obra(deLaObra).material(m).usuario(jefe).build());
    }

    protected Alerta alerta(Obra deLaObra, LocalDate dia, boolean resuelta) {
        return alertaRepository.save(Alerta.builder().tipo(TipoAlerta.STOCK_CRITICO).mensaje("Stock crítico")
                .fecha(dia.atTime(9, 0)).resuelto(resuelta).obra(deLaObra).build());
    }

    protected Herramienta herramienta(String nombre, EstadoHerramienta estado, Empresa deLaEmpresa) {
        return herramientaRepository.save(Herramienta.builder()
                .codigoQr("H-" + UUID.randomUUID()).nombre(nombre).categoria("Eléctrica")
                .estado(estado).valorReposicion(90000).empresa(deLaEmpresa).build());
    }

    protected PrestamoHerramienta prestamo(Herramienta h, Obra deLaObra, boolean devuelto) {
        Usuario u = usuario("peon", RolUsuario.TRABAJADOR, deLaObra.getEmpresa());
        Trabajador t = trabajadorRepository.save(Trabajador.builder().usuario(u).credencialQr("QR-" + UUID.randomUUID()).build());
        return prestamoHerramientaRepository.save(PrestamoHerramienta.builder()
                .herramienta(h).trabajador(t).obra(deLaObra).autorizadoPor(jefe)
                .fechaPrestamo(LocalDateTime.now().minusDays(2)).fechaDevolEsperada(LocalDateTime.now().plusDays(1))
                .fechaDevolReal(devuelto ? LocalDateTime.now().minusHours(1) : null).build());
    }

    // ---- HTTP ------------------------------------------------------------

    protected HttpResponse<String> get(String ruta, String token) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta)).GET();
        if (token != null) {
            b.header("Authorization", "Bearer " + token);
        }
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }

    protected JsonNode ok(String ruta, String token) throws Exception {
        HttpResponse<String> r = get(ruta, token);
        if (r.statusCode() != 200) {
            throw new AssertionError("GET " + ruta + " → " + r.statusCode() + ": " + r.body());
        }
        return json.readTree(r.body());
    }
}
