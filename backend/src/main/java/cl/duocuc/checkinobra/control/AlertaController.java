package cl.duocuc.checkinobra.control;

import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/alertas")
@Tag(name = "Alerta")
public class AlertaController {

    private final AlertaService alertaService;

    public AlertaController(AlertaService alertaService) {
        this.alertaService = alertaService;
    }

    @GetMapping
    public List<Alerta> listar(
            @RequestParam Long obraId, @RequestParam(required = false, defaultValue = "false") boolean soloSinResolver) {
        return soloSinResolver ? alertaService.listarSinResolver(obraId) : alertaService.listarPorObra(obraId);
    }

    /** Resolver una alerta es de BODEGUERO, JEFE_TERRENO o ADMIN, según la matriz de permisos. */
    @PutMapping("/{id}/resolver")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public Alerta resolver(@PathVariable Long id) {
        return alertaService.resolver(id);
    }

    @PostMapping("/detectar-no-devueltas")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<Alerta> detectarNoDevueltas(@RequestParam Long obraId) {
        return alertaService.detectarNoDevueltas(obraId);
    }

    @PostMapping("/detectar-stock-critico")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<Alerta> detectarStockCritico(@RequestParam Long obraId) {
        return alertaService.detectarStockCritico(obraId);
    }

    /** Cerrar turno de bodega es exclusivo de BODEGUERO, según la matriz de permisos. */
    @PostMapping("/cierre-turno")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public Alerta generarCierreTurno(@RequestBody CierreTurnoRequest req) {
        return alertaService.generarCierreTurno(req.obraId(), req.mensaje());
    }

    public record CierreTurnoRequest(Long obraId, String mensaje) {
    }
}
