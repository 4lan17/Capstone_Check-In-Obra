package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG13 (#101): lo que mantiene limpia la base de credenciales.
 *
 * <ul>
 *   <li>La poda borra los códigos que vencieron hace rato, y deja los vigentes y los recién vencidos
 *       (estos últimos siguen respondiendo 409 «caducada» en vez de 404).
 *   <li>La migración V15 borra de las claves de idempotencia las respuestas que ya se habían guardado
 *       con una credencial, y no toca el resto.
 * </ul>
 */
@SpringBootTest
class MantenimientoDeCodigosDeCredencialTest {

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private CodigoCredencialRepository codigoCredencialRepository;
    @Autowired private CodigoCredencialService codigoCredencialService;

    @Value("${checkinobra.catalogo.url}") private String urlCatalogo;
    @Value("${spring.flyway.user}") private String migradorUsuario;
    @Value("${spring.flyway.password}") private String migradorClave;

    private JdbcTemplate comoMigrador;
    private String esquema;
    private Trabajador yo;

    @BeforeEach
    void preparar() {
        String s = UUID.randomUUID().toString().substring(0, 8);
        Empresa empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        Usuario u = usuarioRepository.save(Usuario.builder()
                .nombre("maestro-" + s).email("maestro-" + s + "@test.cl").rol(RolUsuario.TRABAJADOR).empresa(empresa).build());
        yo = trabajadorRepository.save(Trabajador.builder().usuario(u).credencialQr("QR-" + s).build());
        comoMigrador = new JdbcTemplate(new DriverManagerDataSource(urlCatalogo, migradorUsuario, migradorClave));
        esquema = "mig_" + s;
    }

    @AfterEach
    void limpiar() {
        comoMigrador.execute("DROP SCHEMA IF EXISTS " + esquema + " CASCADE");
    }

    // ---- poda ------------------------------------------------------------

    @Test
    void laPodaBorraLosVencidosHaceMasDeLaRetencionYDejaElResto() {
        CodigoCredencial viejo = guardar(CodigosDePrueba.unico(), Instant.now().minus(CodigoCredencialService.RETENCION_DE_VENCIDOS).minusSeconds(60));
        CodigoCredencial recienVencido = guardar(CodigosDePrueba.unico(), Instant.now().minusSeconds(30));
        CodigoCredencial vigente = guardar(CodigosDePrueba.unico(), Instant.now().plusSeconds(100));

        int borrados = codigoCredencialService.podarVencidosDeLaBaseActual();

        assertThat(borrados).isGreaterThanOrEqualTo(1);
        assertThat(codigoCredencialRepository.findById(viejo.getId())).isEmpty();
        assertThat(codigoCredencialRepository.findById(recienVencido.getId())).isPresent();
        assertThat(codigoCredencialRepository.findById(vigente.getId())).isPresent();
    }

    // ---- migración V15 ---------------------------------------------------

    @Test
    void laMigracionBorraLasRespuestasGuardadasConCredencialYNoTocaElResto() {
        comoMigrador.execute("CREATE SCHEMA " + esquema);
        String url = urlCatalogo + "?currentSchema=" + esquema;
        flyway(url).target("14").load().migrate();

        comoMigrador.update("INSERT INTO " + esquema + ".empresas (nombre, rut) VALUES ('E', 'R-MIG')");
        comoMigrador.update("INSERT INTO " + esquema + ".usuarios (nombre, email, rol, empresa_id) "
                + "SELECT 'U', 'u@mig.cl', 'TRABAJADOR', id FROM " + esquema + ".empresas");
        Long usuarioId = comoMigrador.queryForObject("SELECT id FROM " + esquema + ".usuarios", Long.class);
        String conCredencial = clave(usuarioId, "POST", "/api/trabajadores", "{\"id\":1,\"credencialQr\":\"abc\"}".getBytes());
        String rutaDeCredencial = clave(usuarioId, "PUT", "/api/trabajadores/yo/credencial", "{\"id\":1}".getBytes());
        String comun = clave(usuarioId, "POST", "/api/cuadrillas", "{\"id\":7,\"nombre\":\"A\"}".getBytes());
        String binario = clave(usuarioId, "POST", "/api/importacion", new byte[] {(byte) 0xff, 0x00, (byte) 0xfe, 0x01});
        String enCurso = clave(usuarioId, "POST", "/api/obras", null);

        flyway(url).load().migrate();

        assertThat(existe(conCredencial)).as("respuesta con credencialQr").isFalse();
        assertThat(existe(rutaDeCredencial)).as("ruta de credenciales").isFalse();
        assertThat(existe(comun)).as("una escritura cualquiera").isTrue();
        assertThat(existe(binario)).as("un cuerpo binario no rompe la migración").isTrue();
        assertThat(existe(enCurso)).as("una reserva en curso").isTrue();
        assertThat(comoMigrador.queryForObject(
                "SELECT count(*) FROM information_schema.tables WHERE table_schema = ? AND table_name = 'codigos_credencial'",
                Integer.class, esquema)).isEqualTo(1);
    }

    // ---------------------------------------------------------------------

    private CodigoCredencial guardar(String codigo, Instant expiraEn) {
        return codigoCredencialRepository.save(CodigoCredencial.builder()
                .codigo(codigo).trabajador(yo).creadoEn(expiraEn.minusSeconds(120)).expiraEn(expiraEn).build());
    }

    private org.flywaydb.core.api.configuration.FluentConfiguration flyway(String url) {
        return Flyway.configure()
                .dataSource(url, migradorUsuario, migradorClave)
                .locations("classpath:db/migration")
                .ignoreMigrationPatterns("*:missing");
    }

    private String clave(Long usuarioId, String metodo, String ruta, byte[] cuerpo) {
        String clave = UUID.randomUUID().toString();
        comoMigrador.update("INSERT INTO " + esquema + ".claves_idempotencia "
                        + "(usuario_id, clave, huella, metodo, ruta, status, content_type, cuerpo) "
                        + "VALUES (?, CAST(? AS UUID), 'h', ?, ?, ?, 'application/json', ?)",
                usuarioId, clave, metodo, ruta, cuerpo == null ? null : 200, cuerpo);
        return clave;
    }

    private boolean existe(String clave) {
        return comoMigrador.queryForObject("SELECT count(*) FROM " + esquema
                + ".claves_idempotencia WHERE clave = CAST(? AS UUID)", Integer.class, clave) == 1;
    }
}
