package cl.duocuc.checkinobra.inventario;

import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.List;

@RestController
@RequestMapping("/api/solicitudes-herramienta")
@Tag(name = "SolicitudHerramienta")
public class SolicitudHerramientaController {

    private final SolicitudHerramientaService solicitudHerramientaService;

    public SolicitudHerramientaController(SolicitudHerramientaService solicitudHerramientaService) {
        this.solicitudHerramientaService = solicitudHerramientaService;
    }

    /** Solicitar herramienta es exclusivo de TRABAJADOR, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasRole('TRABAJADOR')")
    @ResponseStatus(HttpStatus.CREATED)
    public SolicitudHerramienta crear(@RequestBody CrearSolicitudRequest req) {
        return solicitudHerramientaService.crear(req.trabajadorId(), req.herramientaId(), req.cantidad());
    }

    /** Aprobar/rechazar es de BODEGUERO o ADMIN, según la matriz de permisos. */
    @PutMapping("/{id}/aprobar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public PrestamoHerramienta aprobar(@PathVariable Long id, @RequestBody AprobarRequest req) {
        return solicitudHerramientaService.aprobar(id, req.aprobadorId(), req.fechaDevolEsperada());
    }

    @PutMapping("/{id}/rechazar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public SolicitudHerramienta rechazar(@PathVariable Long id, @RequestBody RechazarRequest req) {
        return solicitudHerramientaService.rechazar(id, req.rechazadorId(), req.motivo());
    }

    @GetMapping("/{id}")
    public SolicitudHerramienta obtener(@PathVariable Long id) {
        return solicitudHerramientaService.obtener(id);
    }

    @GetMapping
    public List<SolicitudHerramienta> listar(
            @RequestParam(required = false) Long trabajadorId,
            @RequestParam(required = false) Long obraId,
            @RequestParam(required = false, defaultValue = "false") boolean soloPendientes) {
        if (trabajadorId != null) {
            return solicitudHerramientaService.listarPorTrabajador(trabajadorId);
        }
        if (obraId != null) {
            return soloPendientes
                    ? solicitudHerramientaService.listarPendientesPorObra(obraId)
                    : solicitudHerramientaService.listarPorObra(obraId);
        }
        throw new IllegalArgumentException("Se requiere trabajadorId u obraId");
    }

    public record CrearSolicitudRequest(Long trabajadorId, Long herramientaId, int cantidad) {
    }

    public record AprobarRequest(Long aprobadorId, LocalDateTime fechaDevolEsperada) {
    }

    public record RechazarRequest(Long rechazadorId, String motivo) {
    }
}
