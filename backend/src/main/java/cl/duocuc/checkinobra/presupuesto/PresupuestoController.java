package cl.duocuc.checkinobra.presupuesto;

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

import java.util.List;

@RestController
@RequestMapping("/api/presupuestos")
@Tag(name = "Presupuesto")
public class PresupuestoController {

    private final PresupuestoService presupuestoService;
    private final ComparadorPresupuestoService comparadorPresupuestoService;

    public PresupuestoController(
            PresupuestoService presupuestoService, ComparadorPresupuestoService comparadorPresupuestoService) {
        this.presupuestoService = presupuestoService;
        this.comparadorPresupuestoService = comparadorPresupuestoService;
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    @ResponseStatus(HttpStatus.CREATED)
    public Presupuesto crear(@RequestBody CrearPresupuestoRequest req) {
        return presupuestoService.crear(req.obraId());
    }

    @GetMapping("/{id}")
    public Presupuesto obtener(@PathVariable Long id) {
        return presupuestoService.obtener(id);
    }

    @GetMapping
    public Presupuesto obtenerPorObra(@RequestParam Long obraId) {
        return presupuestoService.obtenerPorObra(obraId);
    }

    @PostMapping("/{id}/items")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    @ResponseStatus(HttpStatus.CREATED)
    public PresupuestoItem agregarItem(@PathVariable Long id, @RequestBody AgregarItemRequest req) {
        return presupuestoService.agregarItem(id, req.materialId(), req.cantidad());
    }

    @GetMapping("/{id}/items")
    public List<PresupuestoItem> listarItems(@PathVariable Long id) {
        return presupuestoService.listarItems(id);
    }

    @PutMapping("/{id}/aprobar")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    public Presupuesto aprobar(@PathVariable Long id) {
        return presupuestoService.aprobar(id);
    }

    /** Congelar el presupuesto es de JEFE_TERRENO o ADMIN, según la matriz de permisos. */
    @PutMapping("/{id}/congelar")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    public Presupuesto congelar(@PathVariable Long id) {
        return presupuestoService.congelar(id);
    }

    @GetMapping("/{id}/desviacion")
    public ReporteDesviacion desviacion(@PathVariable Long id) {
        return comparadorPresupuestoService.compararVsEjecutado(presupuestoService.obtener(id));
    }

    public record CrearPresupuestoRequest(Long obraId) {
    }

    public record AgregarItemRequest(Long materialId, double cantidad) {
    }
}
