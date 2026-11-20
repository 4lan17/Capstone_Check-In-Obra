package cl.duocuc.checkinobra.config;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.flywaydb.core.Flyway;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Locale;
import java.util.Optional;

/**
 * La base de catálogo: qué empresas existen y cómo conectarse a la base de cada
 * una (MT1, #104).
 *
 * <p>Se conecta con su propio pool, como {@code checkinobra_plataforma}, y no es
 * un {@code DataSource} de Spring: así no desplaza al de la empresa, que es el
 * que usa JPA. Sus migraciones ({@code db/catalogo}) las aplica el migrador al
 * crearse el componente, y si el catálogo no responde la API no arranca.
 *
 * <p>Por ahora el sistema tiene una sola empresa y una sola base, así que el
 * catálogo solo se lee y la API sigue usando esa base como siempre. El
 * enrutador que elige la base por empresa (MT2) se apoya en esto.
 */
@Component
public class CatalogoDeEmpresas implements DisposableBean {

    private static final Logger log = LoggerFactory.getLogger(CatalogoDeEmpresas.class);

    /** De dónde se lee la contraseña de la base actual. Es una referencia, no el secreto. */
    static final String SECRETO_BASE_ACTUAL = "env:SPRING_DATASOURCE_PASSWORD";

    /** Una empresa tal como la guarda el catálogo. */
    public record EmpresaRegistrada(
            Long id, String rut, String nombre, String plan, String estado,
            String nombreBase, String usuarioBase, String secretoRef) {
    }

    private final HikariDataSource pool;
    private final JdbcClient catalogo;
    private final String nombreBaseActual;
    private final String usuarioBaseActual;

    public CatalogoDeEmpresas(
            @Value("${checkinobra.catalogo.url}") String url,
            @Value("${checkinobra.catalogo.username}") String usuario,
            @Value("${checkinobra.catalogo.password}") String clave,
            @Value("${spring.flyway.user}") String migradorUsuario,
            @Value("${spring.flyway.password}") String migradorClave,
            @Value("${spring.datasource.url}") String urlBaseActual,
            @Value("${spring.datasource.username}") String usuarioBaseActual) {
        // Las migraciones del catálogo van con el migrador, igual que las de cada empresa.
        Flyway.configure()
                .dataSource(url, migradorUsuario, migradorClave)
                .locations("classpath:db/catalogo")
                .load()
                .migrate();

        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(url);
        config.setUsername(usuario);
        config.setPassword(clave);
        config.setPoolName("catalogo");
        config.setMaximumPoolSize(3);
        this.pool = new HikariDataSource(config);
        this.catalogo = JdbcClient.create(pool);
        this.nombreBaseActual = nombreDeBase(urlBaseActual);
        this.usuarioBaseActual = usuarioBaseActual;
    }

    /** Todas las empresas registradas. */
    public List<EmpresaRegistrada> listar() {
        return catalogo.sql("""
                        SELECT e.id, e.rut, e.nombre, p.codigo AS plan, e.estado,
                               e.nombre_base, e.usuario_base, e.secreto_ref
                        FROM empresas e JOIN planes p ON p.id = e.plan_id
                        ORDER BY e.id
                        """)
                .query((rs, n) -> new EmpresaRegistrada(
                        rs.getLong("id"), rs.getString("rut"), rs.getString("nombre"), rs.getString("plan"),
                        rs.getString("estado"), rs.getString("nombre_base"), rs.getString("usuario_base"),
                        rs.getString("secreto_ref")))
                .list();
    }

    /** Los datos con que la base actual se registra: su nombre, su usuario y la referencia a su secreto. */
    public String nombreBaseActual() {
        return nombreBaseActual;
    }

    public String usuarioBaseActual() {
        return usuarioBaseActual;
    }

    public String secretoBaseActual() {
        return SECRETO_BASE_ACTUAL;
    }

    public Optional<EmpresaRegistrada> buscarPorBase(String nombreBase) {
        return listar().stream().filter(e -> e.nombreBase().equals(nombreBase)).findFirst();
    }

    public Optional<EmpresaRegistrada> buscarPorRut(String rut) {
        return listar().stream().filter(e -> e.rut().equals(rut)).findFirst();
    }

    /**
     * Registra una empresa y su base. Es idempotente por {@code id}: si ya está, deja al
     * día el nombre y los datos de conexión, pero no el plan ni el estado, que los fija la
     * plataforma y no el arranque.
     *
     * @param id el que ya tiene la empresa en su base, o nulo para que el catálogo asigne uno
     * @return el id de la empresa en el catálogo
     */
    public long registrar(
            Long id, String rut, String nombre, String nombreBase, String usuarioBase, String secretoRef) {
        long asignado = catalogo.sql("""
                        INSERT INTO empresas (id, rut, nombre, plan_id, nombre_base, usuario_base, secreto_ref)
                        VALUES (COALESCE(:id, nextval(pg_get_serial_sequence('empresas', 'id'))), :rut, :nombre,
                                (SELECT id FROM planes WHERE codigo = 'ESTANDAR'), :base, :usuario, :secreto)
                        ON CONFLICT (id) DO UPDATE
                           SET nombre = EXCLUDED.nombre, nombre_base = EXCLUDED.nombre_base,
                               usuario_base = EXCLUDED.usuario_base, secreto_ref = EXCLUDED.secreto_ref
                        RETURNING id
                        """)
                .param("id", id).param("rut", rut).param("nombre", nombre)
                .param("base", nombreBase).param("usuario", usuarioBase).param("secreto", secretoRef)
                .query(Long.class).single();
        // El id puede venir de la base de la empresa: la secuencia se adelanta para que
        // la próxima alta no choque con él.
        catalogo.sql("SELECT setval(pg_get_serial_sequence('empresas', 'id'), (SELECT max(id) FROM empresas))")
                .query().singleValue();
        return asignado;
    }

    /**
     * Reserva un correo para una empresa. Es único en todo el sistema: si ya es de otra,
     * no se pisa y devuelve {@code false}.
     */
    public boolean reservarCorreo(String email, Long empresaId) {
        String correo = normalizar(email);
        catalogo.sql("INSERT INTO indice_login (email, empresa_id) VALUES (:email, :empresa) ON CONFLICT (email) DO NOTHING")
                .param("email", correo).param("empresa", empresaId).update();
        return empresaDeCorreo(correo).equals(Optional.of(empresaId));
    }

    /** Suelta un correo reservado, solo si es de esa empresa (compensa un alta que falló). */
    public void liberarCorreo(String email, Long empresaId) {
        catalogo.sql("DELETE FROM indice_login WHERE email = :email AND empresa_id = :empresa")
                .param("email", normalizar(email)).param("empresa", empresaId).update();
    }

    /** ¿De qué empresa es este correo? Vacío si no está en el índice. */
    public Optional<Long> empresaDeCorreo(String email) {
        if (email == null || email.isBlank()) {
            return Optional.empty();
        }
        return catalogo.sql("SELECT empresa_id FROM indice_login WHERE email = :email")
                .param("email", normalizar(email))
                .query(Long.class)
                .optional();
    }

    static String normalizar(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }

    /** {@code jdbc:postgresql://host:5432/checkinobra?x=y} → {@code checkinobra}. */
    static String nombreDeBase(String jdbcUrl) {
        String sinParametros = jdbcUrl.contains("?") ? jdbcUrl.substring(0, jdbcUrl.indexOf('?')) : jdbcUrl;
        return sinParametros.substring(sinParametros.lastIndexOf('/') + 1);
    }

    @Override
    public void destroy() {
        pool.close();
    }
}
