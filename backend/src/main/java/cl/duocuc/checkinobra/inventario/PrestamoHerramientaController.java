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
@RequestMapping("/api/prestamos-herramienta")
@Tag(name = "PrestamoHerramienta")
public class PrestamoHerramientaController {

    private final PrestamoHerramientaService prestamoHerramientaService;

    public PrestamoHerramientaController(PrestamoHerramientaService prestamoHerramientaService) {
        this.prestamoHerramientaService = prestamoHerramientaService;
    }

    /** Autorizar un préstamo directo (sin solicitud previa) es de BODEGUERO o ADMIN. */
    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    @ResponseStatus(HttpStatus.CREATED)
    public PrestamoHerramienta prestarDirecto(@RequestBody PrestarDirectoRequest req) {
        return prestamoHerramientaService.prestarDirecto(
                req.herramientaId(), req.trabajadorId(), req.obraId(), req.autorizadorId(), req.fechaDevolEsperada());
    }

    @PutMapping("/{id}/devolucion")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public PrestamoHerramienta registrarDevolucion(
            @PathVariable Long id, @RequestBody RegistrarDevolucionRequest req) {
        return prestamoHerramientaService.registrarDevolucion(id, req.nuevoEstadoHerramienta());
    }

    @GetMapping("/{id}")
    public PrestamoHerramienta obtener(@PathVariable Long id) {
        return prestamoHerramientaService.obtener(id);
    }

    @GetMapping
    public List<PrestamoHerramienta> listar(
            @RequestParam(required = false) Long obraId,
            @RequestParam(required = false) Long trabajadorId,
            @RequestParam(required = false, defaultValue = "false") boolean soloVencidos) {
        if (soloVencidos) {
            return prestamoHerramientaService.listarVencidos();
        }
        if (obraId != null) {
            return prestamoHerramientaService.listarPorObra(obraId);
        }
        if (trabajadorId != null) {
            return prestamoHerramientaService.listarPorTrabajador(trabajadorId);
        }
        throw new IllegalArgumentException("Se requiere obraId, trabajadorId o soloVencidos=true");
    }

    public record PrestarDirectoRequest(
            Long herramientaId, Long trabajadorId, Long obraId, Long autorizadorId, LocalDateTime fechaDevolEsperada) {
    }

    public record RegistrarDevolucionRequest(EstadoHerramienta nuevoEstadoHerramienta) {
    }
}
