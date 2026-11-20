package cl.duocuc.checkinobra.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

/**
 * Al arrancar, aplica {@code PRIMER_ADMIN_CLAVE} al administrador inicial si
 * todavía no tiene credencial. Nunca imprime la clave.
 */
@Component
public class PrimerAdminInicializador implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(PrimerAdminInicializador.class);

    private final PrimerAdminService primerAdminService;
    private final String email;
    private final String clave;

    public PrimerAdminInicializador(
            PrimerAdminService primerAdminService,
            @Value("${checkinobra.primer-admin.email:admin@arauco-ltda.cl}") String email,
            @Value("${checkinobra.primer-admin.clave:}") String clave) {
        this.primerAdminService = primerAdminService;
        this.email = email;
        this.clave = clave;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (clave == null || clave.isBlank()) {
            if (primerAdminService.hayAdminSinCredencial(email)) {
                log.warn("El administrador {} no tiene clave y nadie puede entrar con él. "
                        + "Define PRIMER_ADMIN_CLAVE (8 o más caracteres) y reinicia la API.", email);
            }
            return;
        }
        // Una clave que no cumple la política hace fallar el arranque: es una
        // configuración equivocada y conviene verla, no que el admin quede sin acceso.
        if (primerAdminService.fijarClaveInicial(email, clave)) {
            log.info("Se fijó la clave inicial de {}: deberá cambiarla en su primer ingreso.", email);
        }
    }
}
