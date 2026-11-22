package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Mejora #152 (origen: comentario del autor en #103, MT0): el usuario de la API recibía DML sobre
 * todas las tablas, también sobre {@code flyway_schema_history}, porque Flyway la crea después de que
 * corre {@code db/roles.sql} y {@code ALTER DEFAULT PRIVILEGES} se la concedía. Una API comprometida
 * podía borrar o falsear el historial de migraciones. El callback {@code afterMigrate} la deja solo
 * de lectura para la API, en cada migración y por lo tanto en toda base de empresa, también en las
 * dadas de alta después.
 *
 * <p>Las bases de empresa de verdad no se pueden crear acá (el rol de la API no crea bases), así
 * que, como en {@code MigradorDeBasesTest}, se usa un esquema nuevo dentro de la base de catálogo,
 * con los mismos privilegios por defecto que {@code db/roles.sql} da en {@code public}.
 */
@SpringBootTest
class HistorialDeMigracionesProtegidoTest {

    private static final String ROL_API = "checkinobra_app";

    @Autowired private MigradorDeBases migrador;

    @Value("${spring.datasource.url}") private String urlEmpresa;
    @Value("${spring.datasource.username}") private String usuarioEmpresa;
    @Value("${spring.datasource.password}") private String claveEmpresa;
    @Value("${checkinobra.catalogo.url}") private String urlCatalogo;
    @Value("${spring.flyway.user}") private String migradorUsuario;
    @Value("${spring.flyway.password}") private String migradorClave;

    private JdbcTemplate comoMigrador;
    private String esquema;

    @BeforeEach
    void prepararEsquemaComoLoDejaRolesSql() {
        comoMigrador = new JdbcTemplate(new DriverManagerDataSource(urlCatalogo, migradorUsuario, migradorClave));
        esquema = "hist_" + UUID.randomUUID().toString().substring(0, 8);
        comoMigrador.execute("CREATE SCHEMA " + esquema);
        comoMigrador.execute("GRANT USAGE ON SCHEMA " + esquema + " TO " + ROL_API);
        // Lo mismo que db/roles.sql hace en public: lo que el migrador cree queda con DML para la API.
        comoMigrador.execute("ALTER DEFAULT PRIVILEGES FOR ROLE " + migradorUsuario + " IN SCHEMA " + esquema
                + " GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO " + ROL_API);
    }

    @AfterEach
    void limpiar() {
        comoMigrador.execute("DROP SCHEMA IF EXISTS " + esquema + " CASCADE");
    }

    @Test
    void unaBaseRecienMigradaDejaElHistorialSoloDeLecturaParaLaApi() {
        migrador.migrarUrl(urlCatalogo + "?currentSchema=" + esquema);

        assertThat(puede("SELECT", "flyway_schema_history")).isTrue();
        assertThat(puede("INSERT", "flyway_schema_history")).isFalse();
        assertThat(puede("UPDATE", "flyway_schema_history")).isFalse();
        assertThat(puede("DELETE", "flyway_schema_history")).isFalse();
    }

    @Test
    void lasTablasDeDatosSiguenConDmlParaLaApi() {
        migrador.migrarUrl(urlCatalogo + "?currentSchema=" + esquema);

        for (String privilegio : new String[] {"SELECT", "INSERT", "UPDATE", "DELETE"}) {
            assertThat(puede(privilegio, "obras")).as(privilegio + " sobre obras").isTrue();
            assertThat(puede(privilegio, "kardex_movimientos")).as(privilegio + " sobre kardex").isTrue();
        }
    }

    @Test
    void unaBaseYaMigradaQueTeniaElPermisoLoPierdeAlMigrarDeNuevo() {
        String url = urlCatalogo + "?currentSchema=" + esquema;
        migrador.migrarUrl(url);
        // Una base de antes de este cambio: la API todavía tiene DML sobre el historial.
        comoMigrador.execute("GRANT INSERT, UPDATE, DELETE ON " + esquema + ".flyway_schema_history TO " + ROL_API);
        assertThat(puede("DELETE", "flyway_schema_history")).isTrue();

        // No hay migraciones pendientes: el callback corre igual y la corrige.
        migrador.migrarUrl(url);

        assertThat(puede("INSERT", "flyway_schema_history")).isFalse();
        assertThat(puede("UPDATE", "flyway_schema_history")).isFalse();
        assertThat(puede("DELETE", "flyway_schema_history")).isFalse();
    }

    @Test
    void laApiNoPuedeBorrarNiFalsearElHistorialDeLaBaseDeEstaSuite() {
        JdbcTemplate comoLaApi = new JdbcTemplate(new DriverManagerDataSource(urlEmpresa, usuarioEmpresa, claveEmpresa));

        assertThat(comoLaApi.queryForObject("SELECT count(*) FROM flyway_schema_history", Integer.class))
                .isPositive();
        assertThatThrownBy(() -> comoLaApi.update("DELETE FROM flyway_schema_history"))
                .isInstanceOf(DataAccessException.class)
                .rootCause().hasMessageContaining("permission denied");
        assertThatThrownBy(() -> comoLaApi.update("UPDATE flyway_schema_history SET success = false"))
                .isInstanceOf(DataAccessException.class)
                .rootCause().hasMessageContaining("permission denied");
    }

    private boolean puede(String privilegio, String tabla) {
        return Boolean.TRUE.equals(comoMigrador.queryForObject(
                "SELECT has_table_privilege(?, ?, ?)", Boolean.class, ROL_API, esquema + "." + tabla, privilegio));
    }
}
