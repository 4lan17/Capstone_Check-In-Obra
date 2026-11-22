package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.AlmacenDeSecretos;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas.EmpresaRegistrada;
import cl.duocuc.checkinobra.config.MigradorDeBases;
import cl.duocuc.checkinobra.config.PrimeraEmpresaService;
import cl.duocuc.checkinobra.config.ResolutorDeBases;
import cl.duocuc.checkinobra.config.TenantContext;
import cl.duocuc.checkinobra.plataforma.AprovisionadorDeBases.EstadoInterno;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * El barrido de altas a medias (#154, límite anotado en #110 y PR #147).
 *
 * <p>El alta de una constructora ({@link AltaDeEmpresaService}) no es transaccional: registra en el
 * catálogo, reserva el correo, guarda un secreto en un archivo, crea el usuario y la base de PostgreSQL,
 * migra, siembra y crea el ADMIN. Si el proceso se corta en medio, las compensaciones no corren y queda
 * algo de eso sin el resto. Este servicio lo <b>detecta</b>, y deja al operador <b>reanudar</b> el alta
 * o <b>deshacerla</b>.
 *
 * <p>Deshacer borra bases, y por eso es cuidadoso:
 * <ul>
 *   <li>solo toca nombres que siguen la convención del alta ({@code checkinobra_e…}, {@code app_e…}):
 *       nunca la base actual, la de catálogo ni una registrada a mano;</li>
 *   <li>exige que quien llama escriba el identificador exacto;</li>
 *   <li>no borra una base con un ADMIN (parece una empresa en uso) ni una que no pudo revisar: un fallo
 *       de conexión no se interpreta como "está vacía";</li>
 *   <li>deja pasar las empresas registradas hace menos de unos minutos, que pueden ser un alta en curso.</li>
 * </ul>
 */
@Service
public class BarridoDeAltas {

    private static final Logger log = LoggerFactory.getLogger(BarridoDeAltas.class);

    /** Lo que el alta crea: {@code checkinobra_e<dígitos del RUT>} y {@code app_e<dígitos del RUT>}. */
    private static final Pattern BASE_DEL_ALTA = Pattern.compile("checkinobra_e[0-9k]+");
    private static final Pattern USUARIO_DEL_ALTA = Pattern.compile("app_e[0-9k]+");

    public static final String SIN_BASE = "SIN_BASE";
    public static final String SIN_USUARIO_DE_BASE = "SIN_USUARIO_DE_BASE";
    public static final String SIN_SECRETO = "SIN_SECRETO";
    public static final String SIN_MIGRAR = "SIN_MIGRAR";
    public static final String SIN_EMPRESA_EN_SU_BASE = "SIN_EMPRESA_EN_SU_BASE";
    public static final String SIN_ADMINISTRADOR = "SIN_ADMINISTRADOR";
    public static final String NO_SE_PUDO_REVISAR = "NO_SE_PUDO_REVISAR";

    public enum Tipo {
        /** Hay registro en el catálogo, pero le falta algo para estar completa. */
        EMPRESA_A_MEDIAS,
        /** Una base con el nombre del alta que ninguna empresa del catálogo usa. */
        BASE_SIN_REGISTRO,
        /** Un usuario de PostgreSQL con el nombre del alta que ninguna empresa usa. */
        USUARIO_SIN_REGISTRO,
        /** Un archivo de secreto que ninguna empresa referencia. */
        SECRETO_HUERFANO
    }

    /**
     * @param referencia el identificador que hay que escribir para confirmar: el nombre de la base, del
     *     usuario o del secreto
     * @param empresaId solo en {@link Tipo#EMPRESA_A_MEDIAS}
     */
    public record AltaIncompleta(
            Tipo tipo, String referencia, Long empresaId, String nombre, List<String> problemas,
            boolean sePuedeDeshacer, boolean sePuedeReanudar) {
    }

    private record Diagnostico(List<String> problemas, boolean revisada, boolean conAdmin, EstadoInterno interno) {
        boolean sePuedeDeshacer() {
            return revisada && !conAdmin;
        }
    }

    private final CatalogoDeEmpresas catalogo;
    private final AprovisionadorDeBases aprovisionador;
    private final AlmacenDeSecretos secretos;
    private final MigradorDeBases migrador;
    private final ResolutorDeBases resolutor;
    private final PrimeraEmpresaService primeraEmpresa;
    private final Duration gracia;
    /** Una operación que cambia algo a la vez: dos "deshacer" o "reanudar" simultáneos se pisarían. */
    private final Object cerrojo = new Object();

    public BarridoDeAltas(
            CatalogoDeEmpresas catalogo, AprovisionadorDeBases aprovisionador, AlmacenDeSecretos secretos,
            MigradorDeBases migrador, ResolutorDeBases resolutor, PrimeraEmpresaService primeraEmpresa,
            @Value("${checkinobra.plataforma.barrido.gracia-minutos:10}") long graciaMinutos) {
        this.catalogo = catalogo;
        this.aprovisionador = aprovisionador;
        this.secretos = secretos;
        this.migrador = migrador;
        this.resolutor = resolutor;
        this.primeraEmpresa = primeraEmpresa;
        this.gracia = Duration.ofMinutes(graciaMinutos);
    }

    /** ¿Se puede barrer? Hace falta la credencial que mira el servidor de bases (la del alta por API). */
    public boolean disponible() {
        return aprovisionador.disponible();
    }

    // ---- detectar -----------------------------------------------------------------------------

    /** Lo que quedó a medias. Solo mira: no cambia nada. */
    public List<AltaIncompleta> detectar() {
        exigirDisponible();
        List<EmpresaRegistrada> empresas = catalogo.listar();
        List<AltaIncompleta> altas = new ArrayList<>();

        for (EmpresaRegistrada e : empresas) {
            if (!esDelAlta(e) || dentroDeLaGracia(e)) {
                continue;
            }
            Diagnostico d = diagnosticar(e);
            if (!d.problemas().isEmpty()) {
                altas.add(new AltaIncompleta(Tipo.EMPRESA_A_MEDIAS, e.nombreBase(), e.id(), e.nombre(),
                        d.problemas(), d.sePuedeDeshacer(), d.revisada() && sePuedeReanudar(e)));
            }
        }

        Set<String> basesRegistradas = new HashSet<>();
        Set<String> usuariosRegistrados = new HashSet<>();
        Set<String> secretosReferenciados = new HashSet<>();
        for (EmpresaRegistrada e : empresas) {
            basesRegistradas.add(e.nombreBase());
            usuariosRegistrados.add(e.usuarioBase());
            if (e.secretoRef() != null && e.secretoRef().startsWith(AlmacenDeSecretos.PREFIJO)) {
                secretosReferenciados.add(e.secretoRef().substring(AlmacenDeSecretos.PREFIJO.length()));
            }
        }
        for (String base : aprovisionador.basesDeEmpresas()) {
            if (!basesRegistradas.contains(base)) {
                altas.add(huerfana(Tipo.BASE_SIN_REGISTRO, base, sePuedeBorrarLaBase(base)));
            }
        }
        for (String usuario : aprovisionador.usuariosDeEmpresas()) {
            if (!usuariosRegistrados.contains(usuario)) {
                altas.add(huerfana(Tipo.USUARIO_SIN_REGISTRO, usuario, true));
            }
        }
        for (String secreto : secretos.listar()) {
            if (!secretosReferenciados.contains(secreto)) {
                altas.add(huerfana(Tipo.SECRETO_HUERFANO, secreto, true));
            }
        }
        return altas;
    }

    private static AltaIncompleta huerfana(Tipo tipo, String referencia, boolean sePuedeDeshacer) {
        return new AltaIncompleta(tipo, referencia, null, null, List.of(), sePuedeDeshacer, false);
    }

    private Diagnostico diagnosticar(EmpresaRegistrada e) {
        List<String> problemas = new ArrayList<>();
        try {
            boolean hayBase = aprovisionador.existeBase(e.nombreBase());
            if (!hayBase) {
                problemas.add(SIN_BASE);
            }
            if (!aprovisionador.existeUsuario(e.usuarioBase())) {
                problemas.add(SIN_USUARIO_DE_BASE);
            }
            if (!secretos.existe(e.usuarioBase())) {
                problemas.add(SIN_SECRETO);
            }
            EstadoInterno interno = hayBase ? aprovisionador.estadoInterno(e.nombreBase())
                    : new EstadoInterno(false, false, false);
            if (!"OK".equals(e.migracionEstado()) && !interno.admin()) {
                // Una empresa en uso cuya última migración falló tiene ADMIN: eso es otro problema (se ve
                // en /empresas con migracionEstado ERROR), no un alta a medias.
                problemas.add(SIN_MIGRAR);
            }
            if (interno.tablas() && !interno.sembrada()) {
                problemas.add(SIN_EMPRESA_EN_SU_BASE);
            }
            if (!interno.admin()) {
                problemas.add(SIN_ADMINISTRADOR);
            }
            return new Diagnostico(problemas, true, interno.admin(), interno);
        } catch (DataAccessException ex) {
            log.warn("No se pudo revisar el alta de la base {}: {}", e.nombreBase(), ex.getMessage());
            return new Diagnostico(List.of(NO_SE_PUDO_REVISAR), false, false, null);
        }
    }

    private boolean sePuedeReanudar(EmpresaRegistrada e) {
        return catalogo.correoReservado(e.id()).isPresent();
    }

    private boolean sePuedeBorrarLaBase(String base) {
        try {
            return !aprovisionador.estadoInterno(base).admin();
        } catch (DataAccessException ex) {
            return false;
        }
    }

    // ---- deshacer -----------------------------------------------------------------------------

    /**
     * Borra lo que quedó a medias. {@code confirmar} debe ser exactamente {@code referencia}.
     *
     * @throws IllegalArgumentException la confirmación no coincide, o el nombre no es de los que crea el alta (→ 400)
     * @throws NoSuchElementException lo que se quiere deshacer ya no existe (→ 404)
     * @throws IllegalStateException está completa, en uso o no se pudo revisar: no se borra (→ 409)
     */
    public void deshacer(Tipo tipo, String referencia, String confirmar) {
        exigirDisponible();
        if (referencia == null || !referencia.equals(confirmar)) {
            throw new IllegalArgumentException("Para confirmar, escribe el identificador exacto: " + referencia);
        }
        Pattern convencion = tipo == Tipo.EMPRESA_A_MEDIAS || tipo == Tipo.BASE_SIN_REGISTRO
                ? BASE_DEL_ALTA : USUARIO_DEL_ALTA;
        if (!convencion.matcher(referencia).matches()) {
            throw new IllegalArgumentException("«" + referencia + "» no es un nombre de los que crea el alta de empresas");
        }
        synchronized (cerrojo) {
            switch (tipo) {
                case EMPRESA_A_MEDIAS -> deshacerEmpresa(referencia);
                case BASE_SIN_REGISTRO -> deshacerBase(referencia);
                case USUARIO_SIN_REGISTRO -> deshacerUsuario(referencia);
                case SECRETO_HUERFANO -> deshacerSecreto(referencia);
            }
        }
        log.warn("Alta incompleta deshecha: {} {}", tipo, referencia);
    }

    private void deshacerEmpresa(String base) {
        EmpresaRegistrada e = catalogo.buscarPorBase(base)
                .orElseThrow(() -> new NoSuchElementException("No hay una empresa registrada con la base " + base));
        exigirDelAlta(e);
        exigirSinAltaEnCurso(e);
        Diagnostico d = diagnosticar(e);
        if (d.problemas().isEmpty()) {
            throw new IllegalStateException("La empresa está completa: no hay nada que deshacer");
        }
        if (!d.revisada()) {
            throw new IllegalStateException("No se pudo revisar la base de la empresa: no se borra nada");
        }
        if (d.conAdmin()) {
            throw new IllegalStateException(
                    "La base de la empresa ya tiene un administrador: parece estar en uso y no se borra. "
                            + "Se puede reanudar para reparar lo que le falta");
        }
        // Primero fuera del catálogo y con el pool cerrado: con conexiones abiertas la base no se borra.
        catalogo.eliminarEmpresa(e.id());
        resolutor.refrescar();
        aprovisionador.eliminar(e.nombreBase(), e.usuarioBase());
        secretos.borrar(e.usuarioBase());
    }

    private void deshacerBase(String base) {
        if (catalogo.buscarPorBase(base).isPresent()) {
            throw new IllegalStateException("La base pertenece a una empresa registrada: no es huérfana");
        }
        if (!aprovisionador.existeBase(base)) {
            throw new NoSuchElementException("No existe la base " + base);
        }
        if (!sePuedeBorrarLaBase(base)) {
            throw new IllegalStateException(
                    "La base tiene un administrador (o no se pudo revisar): parece una empresa en uso y no se borra");
        }
        aprovisionador.eliminarBase(base);
    }

    private void deshacerUsuario(String usuario) {
        if (catalogo.listar().stream().anyMatch(e -> e.usuarioBase().equals(usuario))) {
            throw new IllegalStateException("El usuario pertenece a una empresa registrada: no es huérfano");
        }
        if (!aprovisionador.existeUsuario(usuario)) {
            throw new NoSuchElementException("No existe el usuario " + usuario);
        }
        aprovisionador.eliminarUsuario(usuario);
    }

    private void deshacerSecreto(String secreto) {
        String referencia = AlmacenDeSecretos.PREFIJO + secreto;
        if (catalogo.listar().stream().anyMatch(e -> referencia.equals(e.secretoRef()))) {
            throw new IllegalStateException("El secreto lo usa una empresa registrada: no es huérfano");
        }
        if (!secretos.existe(secreto)) {
            throw new NoSuchElementException("No existe el secreto " + secreto);
        }
        secretos.borrar(secreto);
    }

    // ---- reanudar -----------------------------------------------------------------------------

    /**
     * Termina un alta cortada: repone el secreto, el usuario y la base si faltan, migra, siembra y crea
     * el ADMIN con el correo que el alta reservó. Cada paso es idempotente. La clave temporal del ADMIN
     * solo viene si hubo que crearlo, y es la única vez que se muestra.
     *
     * <p>No se sabe si el alta original pedía el catálogo base de materiales, así que no se copia: se
     * puede importar después. Tampoco se sabe la clave que el operador eligió, si la eligió.
     *
     * @throws IllegalStateException está completa, no hay correo reservado o no se pudo revisar (→ 409)
     */
    public AltaDeEmpresaService.Resultado reanudar(long empresaId) {
        exigirDisponible();
        synchronized (cerrojo) {
            EmpresaRegistrada e = catalogo.listar().stream().filter(x -> x.id().equals(empresaId)).findFirst()
                    .orElseThrow(() -> new NoSuchElementException("Empresa no encontrada: " + empresaId));
            exigirDelAlta(e);
            exigirSinAltaEnCurso(e);
            Diagnostico d = diagnosticar(e);
            if (d.problemas().isEmpty()) {
                throw new IllegalStateException("La empresa ya está completa");
            }
            if (!d.revisada()) {
                throw new IllegalStateException("No se pudo revisar la base de la empresa: no se reanuda");
            }
            String correo = catalogo.correoReservado(e.id()).orElseThrow(() -> new IllegalStateException(
                    "No quedó reservado el correo del administrador: no se puede reanudar. Se puede deshacer y repetir el alta"));

            if (!secretos.existe(e.usuarioBase())) {
                secretos.guardar(e.usuarioBase(), AltaDeEmpresaService.aleatoria(AltaDeEmpresaService.LARGO_CLAVE_BASE));
            }
            aprovisionador.completar(e.nombreBase(), e.usuarioBase(), secretos.leer(e.usuarioBase()));
            var migracion = migrador.migrar(e);
            if (!migracion.ok()) {
                throw new AltaDeEmpresaException("No se pudo migrar la base de la empresa: " + migracion.error());
            }
            if (!aprovisionador.estadoInterno(e.nombreBase()).sembrada()) {
                aprovisionador.sembrar(e.nombreBase(), e.id(), e.nombre(), e.rut(), false);
            }
            resolutor.refrescar();
            if (!resolutor.conoce(e.id())) {
                throw new AltaDeEmpresaException("No se pudo abrir la base de la empresa");
            }
            String claveTemporal = null;
            if (!aprovisionador.estadoInterno(e.nombreBase()).admin()) {
                String clave = AltaDeEmpresaService.aleatoria(AltaDeEmpresaService.LARGO_CLAVE_TEMPORAL);
                boolean creado = TenantContext.ejecutarEn(e.id(),
                        () -> primeraEmpresa.crearAdminSiNoHay(e.rut(), correo, clave));
                if (!creado) {
                    throw new AltaDeEmpresaException("No se pudo crear el administrador de la empresa");
                }
                claveTemporal = clave;
            }
            log.warn("Alta reanudada: empresa {} (base {}).", e.id(), e.nombreBase());
            return new AltaDeEmpresaService.Resultado(e.id(), e.rut(), e.nombre(), correo, claveTemporal);
        }
    }

    // ---- ayudas -------------------------------------------------------------------------------

    /** Solo las empresas que dio de alta la API: las registradas a mano (secreto {@code env:}) no se tocan. */
    private static boolean esDelAlta(EmpresaRegistrada e) {
        return e.secretoRef() != null && e.secretoRef().startsWith(AlmacenDeSecretos.PREFIJO)
                && BASE_DEL_ALTA.matcher(e.nombreBase()).matches()
                && USUARIO_DEL_ALTA.matcher(e.usuarioBase()).matches();
    }

    private static void exigirDelAlta(EmpresaRegistrada e) {
        if (!esDelAlta(e)) {
            throw new IllegalArgumentException("La empresa no la dio de alta la API: no se toca desde acá");
        }
    }

    /** Un alta en curso también se ve a medias; las muy recientes se dejan pasar. */
    private boolean dentroDeLaGracia(EmpresaRegistrada e) {
        return catalogo.creadaEn(e.id()).map(c -> Instant.now().isBefore(c.plus(gracia))).orElse(false);
    }

    private void exigirSinAltaEnCurso(EmpresaRegistrada e) {
        if (dentroDeLaGracia(e)) {
            throw new IllegalStateException(
                    "La empresa se registró hace pocos minutos: puede ser un alta en curso. Vuelve a intentarlo más tarde");
        }
    }

    private void exigirDisponible() {
        if (!aprovisionador.disponible()) {
            throw new IllegalStateException(
                    "El barrido de altas no está habilitado: falta la credencial del aprovisionador de bases");
        }
    }
}
