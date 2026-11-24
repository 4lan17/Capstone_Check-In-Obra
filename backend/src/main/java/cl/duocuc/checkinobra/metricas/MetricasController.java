package cl.duocuc.checkinobra.metricas;

import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Métricas de solo lectura (#203). {@code ?periodo=7d|30d|obra}, por defecto 30d, en America/Santiago.
 */
@RestController
@RequestMapping("/api")
@Tag(name = "Métricas")
public class MetricasController {

    private final MetricasService metricasService;

    public MetricasController(MetricasService metricasService) {
        this.metricasService = metricasService;
    }

    /** El jefe de terreno de la obra y el administrador. */
    @GetMapping("/obras/{id}/metricas/jefe")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    public MetricasJefeResponse jefe(@PathVariable Long id, @RequestParam(required = false) String periodo) {
        return metricasService.jefe(id, periodo);
    }

    @GetMapping("/obras/{id}/metricas/bodega")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public MetricasBodegaResponse bodega(@PathVariable Long id, @RequestParam(required = false) String periodo) {
        return metricasService.bodega(id, periodo);
    }

    @GetMapping("/metricas/empresa")
    @PreAuthorize("hasRole('ADMIN')")
    public MetricasEmpresaResponse empresa(@RequestParam(required = false) String periodo) {
        return metricasService.empresa(periodo);
    }
}
