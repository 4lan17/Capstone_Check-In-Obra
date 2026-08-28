package cl.duocuc.checkinobra.obra;

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
@RequestMapping("/api/obras")
@Tag(name = "Obra")
public class ObraController {

    private final ObraService obraService;

    public ObraController(ObraService obraService) {
        this.obraService = obraService;
    }

    /** Crear y cerrar obras es exclusivo de ADMIN, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    @ResponseStatus(HttpStatus.CREATED)
    public Obra crear(@RequestBody CrearObraRequest req) {
        return obraService.crear(req.empresaId(), req.nombre(), req.cliente(), req.ubicacion());
    }

    @GetMapping
    public List<Obra> listarPorEmpresa(@RequestParam Long empresaId) {
        return obraService.listarPorEmpresa(empresaId);
    }

    @GetMapping("/{id}")
    public Obra obtener(@PathVariable Long id) {
        return obraService.obtener(id);
    }

    @PutMapping("/{id}/cerrar")
    @PreAuthorize("hasRole('ADMIN')")
    public Obra cerrar(@PathVariable Long id) {
        return obraService.cerrarObra(id);
    }

    public record CrearObraRequest(Long empresaId, String nombre, String cliente, String ubicacion) {
    }
}
