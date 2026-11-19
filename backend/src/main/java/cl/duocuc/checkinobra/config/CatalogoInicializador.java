package cl.duocuc.checkinobra.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Al arrancar, deja registrada en el catálogo a la empresa de la base actual y
 * cuenta cuántas empresas conoce. Corre después de crear la primera empresa.
 */
@Component
@Order(20)
public class CatalogoInicializador implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(CatalogoInicializador.class);

    private final CatalogoDeEmpresas catalogo;
    private final String rutEmpresa;

    public CatalogoInicializador(
            CatalogoDeEmpresas catalogo,
            @Value("${checkinobra.primera-empresa.rut:76.412.330-9}") String rutEmpresa) {
        this.catalogo = catalogo;
        this.rutEmpresa = rutEmpresa;
    }

    @Override
    public void run(ApplicationArguments args) {
        catalogo.registrarBaseActual(rutEmpresa)
                .ifPresentOrElse(
                        e -> log.info("Catálogo: la base «{}» es la de la empresa {}.", e.nombreBase(), e.rut()),
                        () -> log.warn("Catálogo: la empresa {} no está en la base actual; no se registró.", rutEmpresa));
        log.info("Catálogo: {} empresa(s) registrada(s).", catalogo.listar().size());
    }
}
