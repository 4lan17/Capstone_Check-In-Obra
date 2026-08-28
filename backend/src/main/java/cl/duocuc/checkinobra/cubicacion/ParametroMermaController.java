package cl.duocuc.checkinobra.cubicacion;

import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.NoSuchElementException;

@RestController
@RequestMapping("/api/materiales/{materialId}/merma")
@Tag(name = "ParametroMerma")
public class ParametroMermaController {

    private final ParametroMermaService parametroMermaService;

    public ParametroMermaController(ParametroMermaService parametroMermaService) {
        this.parametroMermaService = parametroMermaService;
    }

    /** Definir parámetros de merma es exclusivo de ADMIN, según la matriz de permisos. */
    @PutMapping
    @PreAuthorize("hasRole('ADMIN')")
    public ParametroMerma definir(@PathVariable Long materialId, @RequestBody DefinirMermaRequest req) {
        return parametroMermaService.definirParaMaterial(materialId, req.porcentaje());
    }

    @GetMapping
    public ParametroMerma obtener(@PathVariable Long materialId) {
        return parametroMermaService.paraMaterial(materialId)
                .orElseThrow(() -> new NoSuchElementException("El material no tiene parámetro de merma propio"));
    }

    public record DefinirMermaRequest(double porcentaje) {
    }
}
