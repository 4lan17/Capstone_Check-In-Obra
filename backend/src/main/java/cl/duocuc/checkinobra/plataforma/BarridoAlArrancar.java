package cl.duocuc.checkinobra.plataforma;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Al arrancar, avisa en el log si quedó algo de un alta cortada (#154). Solo mira: lo que se hace con
 * eso lo decide el operador desde {@code /api/plataforma/altas-incompletas}. Nunca impide arrancar.
 */
@Component
@Order(30)
public class BarridoAlArrancar implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(BarridoAlArrancar.class);

    private final BarridoDeAltas barrido;

    public BarridoAlArrancar(BarridoDeAltas barrido) {
        this.barrido = barrido;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (!barrido.disponible()) {
            return;
        }
        try {
            var altas = barrido.detectar();
            if (altas.isEmpty()) {
                log.info("Barrido de altas: no hay nada a medias.");
                return;
            }
            log.warn("Barrido de altas: {} resto(s) de altas de empresa sin terminar. Revisa "
                    + "GET /api/plataforma/altas-incompletas.", altas.size());
            altas.forEach(a -> log.warn("Alta incompleta: tipo={} referencia={} problemas={}",
                    a.tipo(), a.referencia(), a.problemas()));
        } catch (RuntimeException e) {
            log.error("El barrido de altas al arrancar falló y se omite: {}", e.getMessage());
        }
    }
}
