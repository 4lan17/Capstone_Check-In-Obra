package cl.duocuc.checkinobra.obra;

import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/cuadrillas")
@Tag(name = "Cuadrilla")
public class CuadrillaController {

    private final CuadrillaService cuadrillaService;

    public CuadrillaController(CuadrillaService cuadrillaService) {
        this.cuadrillaService = cuadrillaService;
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    @ResponseStatus(HttpStatus.CREATED)
    public CuadrillaResponse crear(@RequestBody CrearCuadrillaRequest req) {
        return CuadrillaResponse.de(cuadrillaService.crear(req.obraId(), req.nombre()));
    }

    @GetMapping
    public List<CuadrillaResponse> listarPorObra(@RequestParam Long obraId) {
        return cuadrillaService.listarPorObra(obraId).stream().map(CuadrillaResponse::de).toList();
    }

    @GetMapping("/{id}")
    public CuadrillaResponse obtener(@PathVariable Long id) {
        return CuadrillaResponse.de(cuadrillaService.obtener(id));
    }

    public record CrearCuadrillaRequest(Long obraId, String nombre) {
    }
}
