package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.UrlsDeBases;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

/**
 * La parte de infraestructura del alta de una empresa (MT7, #110): crea su base y su usuario de
 * PostgreSQL, y la prepara para que el migrador y la API trabajen en ella.
 *
 * <p>Usa <b>tres credenciales distintas</b>, cada una con lo mínimo:
 * <ul>
 *   <li>el aprovisionador ({@code CREATEDB} y {@code CREATEROLE}) solo crea el usuario y la base, y
 *       los borra si el alta falla;</li>
 *   <li>el migrador, dueño de la base, hace lo que está <em>dentro</em> de ella: permisos, el
 *       esquema (lo aplica Flyway) y los datos iniciales;</li>
 *   <li>el usuario de la empresa, que recibe solo DML y se conecta únicamente a su base.</li>
 * </ul>
 * Los nombres se validan antes de llegar al SQL y se escriben con {@code format(%I)}, que los cita.
 */
@Component
public class AprovisionadorDeBases {

    /** Un nombre de base o de usuario que esta clase acepta. */
    private static final Pattern NOMBRE = Pattern.compile("[a-z][a-z0-9_]{2,40}");

    private final UrlsDeBases urls;
    private final String migradorUsuario;
    private final String migradorClave;
    private final String usuario;
    private final String clave;

    public AprovisionadorDeBases(
            @Value("${spring.datasource.url}") String urlDelServidor,
            @Value("${spring.flyway.user}") String migradorUsuario,
            @Value("${spring.flyway.password}") String migradorClave,
            @Value("${checkinobra.plataforma.aprovisionador.username:checkinobra_aprovisionador}") String usuario,
            @Value("${checkinobra.plataforma.aprovisionador.password:}") String clave) {
        this.urls = new UrlsDeBases(urlDelServidor);
        this.migradorUsuario = migradorUsuario;
        this.migradorClave = migradorClave;
        this.usuario = usuario;
        this.clave = clave;
    }

    /** ¿Está configurada la credencial que crea bases? Sin ella el alta por API no está disponible. */
    public boolean disponible() {
        return clave != null && !clave.isBlank();
    }

    public static boolean nombreValido(String nombre) {
        return nombre != null && NOMBRE.matcher(nombre).matches();
    }

    /** Crea el usuario y la base, vacía, con el migrador como dueño, y deja los permisos puestos. */
    public void crear(String base, String usuarioBase, String claveBase) {
        exigirNombres(base, usuarioBase);
        JdbcTemplate comoAprovisionador = conectar("postgres", usuario, clave);
        ejecutar(comoAprovisionador,
                "SELECT format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION', ?::text, ?::text)",
                usuarioBase, claveBase);
        ejecutar(comoAprovisionador, "SELECT format('CREATE DATABASE %I OWNER checkinobra_migrador', ?::text)", base);

        darPermisos(base, usuarioBase);
    }

    /**
     * Lo que {@link #crear} deja puesto dentro de la base, como dueño: solo el usuario de la empresa y
     * el migrador se conectan, y la API recibe DML sobre lo que el migrador cree, sin poder cambiar el
     * esquema. Es idempotente: sirve también para reanudar un alta cortada.
     */
    private void darPermisos(String base, String usuarioBase) {
        JdbcTemplate comoMigrador = conectar(base, migradorUsuario, migradorClave);
        ejecutar(comoMigrador, "SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', ?::text)", base);
        ejecutar(comoMigrador, "SELECT format('GRANT CONNECT ON DATABASE %I TO %I', ?::text, ?::text)", base, usuarioBase);
        comoMigrador.execute("ALTER SCHEMA public OWNER TO " + migradorUsuarioCitado());
        ejecutar(comoMigrador, "SELECT format('GRANT USAGE ON SCHEMA public TO %I', ?::text)", usuarioBase);
        ejecutar(comoMigrador, "SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public "
                + "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I', ?::text, ?::text)", migradorUsuario, usuarioBase);
        ejecutar(comoMigrador, "SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public "
                + "GRANT USAGE, SELECT ON SEQUENCES TO %I', ?::text, ?::text)", migradorUsuario, usuarioBase);
    }

    /** La empresa y, opcionalmente, el catálogo base de materiales, con el esquema ya migrado. */
    public void sembrar(String base, long empresaId, String nombre, String rut, boolean copiarCatalogoBase) {
        exigirNombres(base, null);
        JdbcTemplate comoMigrador = conectar(base, migradorUsuario, migradorClave);
        // La empresa lleva en su base el mismo id que tiene en el catálogo: es el que viaja en el JWT.
        comoMigrador.update("INSERT INTO empresas (id, nombre, rut) VALUES (?, ?::text, ?::text)", empresaId, nombre, rut);
        comoMigrador.queryForObject("SELECT setval(pg_get_serial_sequence('empresas', 'id'), (SELECT max(id) FROM empresas))",
                Long.class);
        if (copiarCatalogoBase) {
            for (String[] m : leerCatalogoBase()) {
                comoMigrador.update("""
                                INSERT INTO materiales (sku, nombre, categoria, precio_unitario, stock_minimo, empresa_id)
                                VALUES (?, ?, ?, ?, ?, ?)
                                """,
                        m[0], m[1], m[2], Double.parseDouble(m[3]), Double.parseDouble(m[4]), empresaId);
            }
        }
    }

    /**
     * Deshace {@link #crear}: borra la base y el usuario. No falla si ya no existen. Falla si alguien
     * sigue conectado a la base: hay que cerrar antes el pool de la empresa.
     */
    public void eliminar(String base, String usuarioBase) {
        exigirNombres(base, usuarioBase);
        // El dueño de la base es el migrador: la borra él, conectado a otra base.
        ejecutar(conectar("postgres", migradorUsuario, migradorClave),
                "SELECT format('DROP DATABASE IF EXISTS %I', ?::text)", base);
        ejecutar(conectar("postgres", usuario, clave), "SELECT format('DROP ROLE IF EXISTS %I', ?::text)", usuarioBase);
    }

    /** Borra solo una base (la de una restauración de prueba, por ejemplo); el usuario se deja. */
    public void eliminarBase(String base) {
        exigirNombres(base, null);
        ejecutar(conectar("postgres", migradorUsuario, migradorClave),
                "SELECT format('DROP DATABASE IF EXISTS %I', ?::text)", base);
    }

    public boolean existeBase(String base) {
        exigirNombres(base, null);
        return Boolean.TRUE.equals(conectar("postgres", usuario, clave)
                .queryForObject("SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = ?)", Boolean.class, base));
    }

    /** Lo que se ve por dentro de la base de una empresa para saber hasta dónde llegó su alta. */
    public record EstadoInterno(boolean tablas, boolean sembrada, boolean admin) {
    }

    /**
     * Deja al día lo que un alta cortada pudo no terminar (#154): crea el usuario y la base si faltan,
     * pone al usuario la clave del secreto (si el secreto se perdió y se regeneró, la vieja ya no sirve)
     * y repone los permisos. Solo se llama con nombres que siguen la convención del alta.
     */
    public void completar(String base, String usuarioBase, String claveBase) {
        exigirNombres(base, usuarioBase);
        JdbcTemplate comoAprovisionador = conectar("postgres", usuario, clave);
        ejecutar(comoAprovisionador, existeUsuario(usuarioBase)
                        ? "SELECT format('ALTER ROLE %I PASSWORD %L', ?::text, ?::text)"
                        : "SELECT format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION', ?::text, ?::text)",
                usuarioBase, claveBase);
        if (!existeBase(base)) {
            ejecutar(comoAprovisionador, "SELECT format('CREATE DATABASE %I OWNER checkinobra_migrador', ?::text)", base);
        }
        darPermisos(base, usuarioBase);
    }

    /**
     * Hasta dónde llegó el alta de una base que existe: ¿tiene el esquema, la fila de su empresa y un
     * ADMIN? Se mira como el migrador (dueño), así que no depende del secreto, que puede haberse perdido.
     *
     * <p>Un fallo de conexión o de consulta se propaga: no se interpreta como "la base está vacía", porque
     * con eso alguien podría borrar una base en uso.
     *
     * @throws org.springframework.dao.DataAccessException si no se pudo mirar
     */
    public EstadoInterno estadoInterno(String base) {
        exigirNombres(base, null);
        JdbcTemplate comoMigrador = conectar(base, migradorUsuario, migradorClave);
        boolean tablas = Boolean.TRUE.equals(comoMigrador.queryForObject(
                "SELECT to_regclass('public.empresas') IS NOT NULL AND to_regclass('public.usuarios') IS NOT NULL",
                Boolean.class));
        if (!tablas) {
            return new EstadoInterno(false, false, false);
        }
        boolean sembrada = Boolean.TRUE.equals(comoMigrador.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM empresas)", Boolean.class));
        boolean admin = Boolean.TRUE.equals(comoMigrador.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM usuarios WHERE rol = 'ADMIN')", Boolean.class));
        return new EstadoInterno(true, sembrada, admin);
    }

    public boolean existeUsuario(String usuarioBase) {
        exigirNombres(usuarioBase, null);
        return Boolean.TRUE.equals(conectar("postgres", usuario, clave)
                .queryForObject("SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ?)", Boolean.class, usuarioBase));
    }

    /** Las bases del servidor con el nombre que da el alta ({@code checkinobra_e<dígitos del RUT>}). */
    public java.util.List<String> basesDeEmpresas() {
        return conectar("postgres", usuario, clave).queryForList(
                "SELECT datname FROM pg_database WHERE datname ~ '^checkinobra_e[0-9k]+$' ORDER BY datname", String.class);
    }

    /** Los usuarios de PostgreSQL con el nombre que da el alta ({@code app_e<dígitos del RUT>}). */
    public java.util.List<String> usuariosDeEmpresas() {
        return conectar("postgres", usuario, clave).queryForList(
                "SELECT rolname FROM pg_roles WHERE rolname ~ '^app_e[0-9k]+$' ORDER BY rolname", String.class);
    }

    /** Borra solo un usuario (el de una base que ya no está). No falla si no existe. */
    public void eliminarUsuario(String usuarioBase) {
        exigirNombres(usuarioBase, null);
        ejecutar(conectar("postgres", usuario, clave), "SELECT format('DROP ROLE IF EXISTS %I', ?::text)", usuarioBase);
    }

    /** Las filas del catálogo base: sku, nombre, categoría, precio de referencia y stock mínimo. */
    public static java.util.List<String[]> leerCatalogoBase() {
        try (var lector = new BufferedReader(new InputStreamReader(
                new ClassPathResource("db/catalogo-base/materiales.csv").getInputStream(), StandardCharsets.UTF_8))) {
            return lector.lines().skip(1).filter(l -> !l.isBlank()).map(l -> l.split(";")).toList();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private String migradorUsuarioCitado() {
        // Viene de la configuración, no de una petición; igual se cita.
        return "\"" + migradorUsuario.replace("\"", "\"\"") + "\"";
    }

    private static void exigirNombres(String base, String usuarioBase) {
        if (!nombreValido(base) || (usuarioBase != null && !nombreValido(usuarioBase))) {
            throw new IllegalArgumentException("Nombre de base o de usuario no válido");
        }
    }

    /** Arma el SQL con {@code format(%I, %L)} en el servidor y lo ejecuta: los nombres nunca se concatenan. */
    private static void ejecutar(JdbcTemplate jdbc, String formato, Object... parametros) {
        String sql = jdbc.queryForObject(formato, String.class, parametros);
        jdbc.execute(sql);
    }

    private JdbcTemplate conectar(String base, String usuarioConexion, String claveConexion) {
        return new JdbcTemplate(new DriverManagerDataSource(urls.de(base), usuarioConexion, claveConexion));
    }
}
