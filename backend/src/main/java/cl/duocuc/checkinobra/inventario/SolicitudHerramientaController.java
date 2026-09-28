package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.SesionActual;
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
    public SolicitudHerramientaResponse crear(@RequestBody CrearSolicitudRequest req) {
        return SolicitudHerramientaResponse.de(
                solicitudHerramientaService.crear(
                        // Se pide a nombre propio, igual que una solicitud de material.
                        SesionActual.usuarioId(), req.herramientaId(), req.cantidad()));
    }

    /** Aprobar/rechazar es de BODEGUERO o ADMIN, según la matriz de permisos. */
    @PutMapping("/{id}/aprobar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public PrestamoHerramientaResponse aprobar(@PathVariable Long id, @RequestBody AprobarRequest req) {
        // Aprobar una solicitud produce el préstamo, no la solicitud.
        return PrestamoHerramientaResponse.de(
                solicitudHerramientaService.aprobar(id, SesionActual.usuarioId(), req.fechaDevolEsperada()));
    }

    @PutMapping("/{id}/rechazar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public SolicitudHerramientaResponse rechazar(@PathVariable Long id, @RequestBody RechazarRequest req) {
        return SolicitudHerramientaResponse.de(
                solicitudHerramientaService.rechazar(id, SesionActual.usuarioId(), req.motivo()));
    }

    @GetMapping("/{id}")
    public SolicitudHerramientaResponse obtener(@PathVariable Long id) {
        return SolicitudHerramientaResponse.de(solicitudHerramientaService.obtener(id));
    }

    @GetMapping
    public List<SolicitudHerramientaResponse> listar(
            @RequestParam(required = false) Long trabajadorId,
            @RequestParam(required = false) Long obraId,
            @RequestParam(required = false, defaultValue = "false") boolean soloPendientes) {
        List<SolicitudHerramienta> solicitudes;
        if (trabajadorId != null) {
            solicitudes = solicitudHerramientaService.listarPorTrabajador(trabajadorId);
        } else if (obraId != null) {
            solicitudes = soloPendientes
                    ? solicitudHerramientaService.listarPendientesPorObra(obraId)
                    : solicitudHerramientaService.listarPorObra(obraId);
        } else {
            throw new IllegalArgumentException("Se requiere trabajadorId u obraId");
        }
        return solicitudes.stream().map(SolicitudHerramientaResponse::de).toList();
    }

    public record CrearSolicitudRequest(Long herramientaId, int cantidad) {
    }

    public record AprobarRequest(LocalDateTime fechaDevolEsperada) {
    }

    public record RechazarRequest(String motivo) {
    }
}
