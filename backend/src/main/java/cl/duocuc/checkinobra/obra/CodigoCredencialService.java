package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.config.DemasiadosIntentosException;
import cl.duocuc.checkinobra.config.LimitadorDeIntentos;
import cl.duocuc.checkinobra.config.ResolutorDeBases;
import cl.duocuc.checkinobra.config.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.NoSuchElementException;
import java.util.regex.Pattern;

/**
 * Códigos de credencial de vida corta (SEG13, S-27): el trabajador pide uno a su teléfono, el
 * bodeguero lo escanea y el servidor lo canjea por el trabajador, si sigue vigente.
 *
 * <p>El código se guarda del lado del servidor con su expiración, no va firmado: por eso renovar la
 * credencial lo puede revocar. Cada pedido emite uno nuevo y los anteriores valen hasta que vencen
 * (la app renueva cada ~60 s con una vigencia de 120 s, así que siempre hay un traslape).
 *
 * <p>Canjear es la superficie que se puede atacar: 8 caracteres de un alfabeto de 32 son 2^40
 * combinaciones, y tienen que acertar dentro de la vigencia. Aun así, los escaneos que no reconocen
 * el código se cuentan por quien escanea y bloquean con 429 pasado el tope ({@link LimitadorDeIntentos},
 * el mismo del login). Un código vencido no cuenta: ahí el código era real.
 */
@Service
public class CodigoCredencialService {

    private static final Logger log = LoggerFactory.getLogger(CodigoCredencialService.class);

    /**
     * Cuánto se conserva un código después de vencer. Es para poder decir «caducó» (409) en vez de «no
     * existe» (404) a quien escanea una pantalla que se le quedó vieja; pasado ese rato se poda.
     */
    public static final Duration RETENCION_DE_VENCIDOS = Duration.ofHours(1);

    /** 24 letras (sin I ni O) y 8 dígitos (sin 0 ni 1): 32 símbolos, 5 bits cada uno, sin ambiguos. */
    static final String ALFABETO = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    static final int LARGO = 8;
    private static final Pattern FORMATO = Pattern.compile("[A-HJ-NP-Z2-9]{" + LARGO + "}");
    private static final Pattern SEPARADORES = Pattern.compile("[\\s-]");
    private static final int INTENTOS_DE_EMISION = 5;
    private static final SecureRandom ALEATORIO = new SecureRandom();

    private final CodigoCredencialRepository repositorio;
    private final JdbcTemplate jdbc;
    private final ResolutorDeBases resolutor;
    private final Duration vigencia;
    private final LimitadorDeIntentos limitador;
    private final Clock reloj = Clock.systemUTC();

    public CodigoCredencialService(
            CodigoCredencialRepository repositorio,
            JdbcTemplate jdbc,
            ResolutorDeBases resolutor,
            @Value("${checkinobra.credencial.vigencia-segundos:120}") long vigenciaSegundos,
            @Value("${checkinobra.credencial.escaneo.max-fallos:20}") int maxFallos,
            @Value("${checkinobra.credencial.escaneo.bloqueo-base-segundos:30}") long bloqueoBase,
            @Value("${checkinobra.credencial.escaneo.bloqueo-maximo-segundos:600}") long bloqueoMaximo,
            @Value("${checkinobra.credencial.escaneo.olvido-segundos:600}") long olvido) {
        this.repositorio = repositorio;
        this.jdbc = jdbc;
        this.resolutor = resolutor;
        this.vigencia = Duration.ofSeconds(vigenciaSegundos);
        this.limitador = new LimitadorDeIntentos(maxFallos, Duration.ofSeconds(bloqueoBase),
                Duration.ofSeconds(bloqueoMaximo), Duration.ofSeconds(olvido), reloj);
    }

    /** Emite un código nuevo para el trabajador. Los que ya tenía siguen valiendo hasta que venzan. */
    @Transactional
    public CodigoCredencialResponse emitir(Trabajador trabajador) {
        Instant ahora = reloj.instant();
        for (int intento = 0; intento < INTENTOS_DE_EMISION; intento++) {
            String codigo = generar();
            if (!repositorio.existsByCodigo(codigo)) {
                CodigoCredencial guardado = repositorio.save(CodigoCredencial.builder()
                        .codigo(codigo).trabajador(trabajador).creadoEn(ahora).expiraEn(ahora.plus(vigencia)).build());
                return new CodigoCredencialResponse(guardado.getCodigo(), guardado.getExpiraEn(), (int) vigencia.toSeconds());
            }
        }
        throw new IllegalStateException("No se pudo emitir un código único de credencial");
    }

    /**
     * Canjea el código que el bodeguero escaneó por el trabajador.
     *
     * @param escaneadoPor quien escanea; el tope de intentos fallidos es suyo
     * @throws NoSuchElementException código desconocido, revocado, de otra empresa o con otro formato (404)
     * @throws ConflictoException {@code CREDENCIAL_CADUCADA} si existe pero ya venció (409)
     * @throws DemasiadosIntentosException si quien escanea acumuló demasiados códigos desconocidos (429)
     */
    @Transactional(readOnly = true)
    public Trabajador canjear(String escrito, Long empresaId, Long escaneadoPor) {
        String quien = empresaId + ":" + escaneadoPor;
        limitador.bloqueoRestante(quien).ifPresent(espera -> {
            throw new DemasiadosIntentosException(espera);
        });

        String codigo = normalizar(escrito);
        CodigoCredencial encontrado = FORMATO.matcher(codigo).matches()
                // Un código de otra empresa no se resuelve, y tampoco delata que existe.
                ? repositorio.findByCodigo(codigo).filter(AccesoEmpresa::esPropio).orElse(null)
                : null;
        if (encontrado == null) {
            limitador.registrarFallo(quien);
            throw new NoSuchElementException("Credencial no reconocida");
        }
        if (encontrado.vencidoEn(reloj.instant())) {
            throw new ConflictoException(ConflictoException.CREDENCIAL_CADUCADA,
                    "La credencial venció. Pídele al trabajador que muestre el código actualizado en su teléfono.");
        }
        limitador.registrarExito(quien);
        return encontrado.getTrabajador();
    }

    /** Anula todos los códigos del trabajador, vigentes o no (renovar la credencial). */
    @Transactional
    public int revocarTodos(Long trabajadorId) {
        return repositorio.borrarDelTrabajador(trabajadorId);
    }

    /** Mayúsculas, sin guiones ni espacios: la app lo muestra como {@code K7M2-9QXP}. */
    static String normalizar(String escrito) {
        return escrito == null ? "" : SEPARADORES.matcher(escrito).replaceAll("").toUpperCase(Locale.ROOT);
    }

    private static String generar() {
        StringBuilder codigo = new StringBuilder(LARGO);
        for (int i = 0; i < LARGO; i++) {
            codigo.append(ALFABETO.charAt(ALEATORIO.nextInt(ALFABETO.length())));
        }
        return codigo.toString();
    }

    /** Borra los códigos de la base de la empresa en curso que vencieron hace más de la retención. */
    public int podarVencidosDeLaBaseActual() {
        return jdbc.update("DELETE FROM codigos_credencial WHERE expira_en < ?",
                Timestamp.from(reloj.instant().minus(RETENCION_DE_VENCIDOS)));
    }

    @Scheduled(cron = "0 23 * * * *")
    public void podarVencidos() {
        // Corre fuera de una petición: no hay empresa en el contexto, así que recorre las de todas
        // las bases y fija la de cada una. Si una falla se anota y sigue con las demás.
        for (Long empresaId : resolutor.empresas()) {
            try {
                TenantContext.ejecutarEn(empresaId, () -> {
                    podarVencidosDeLaBaseActual();
                });
            } catch (RuntimeException e) {
                log.error("No se pudo podar los códigos de credencial de la empresa {}: {}", empresaId, e.getMessage());
            }
        }
    }
}
