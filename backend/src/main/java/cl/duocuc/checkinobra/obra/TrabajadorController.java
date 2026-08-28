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
@RequestMapping("/api/trabajadores")
@Tag(name = "Trabajador")
public class TrabajadorController {

    private final TrabajadorService trabajadorService;

    public TrabajadorController(TrabajadorService trabajadorService) {
        this.trabajadorService = trabajadorService;
    }

    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    @ResponseStatus(HttpStatus.CREATED)
    public Trabajador crear(@RequestBody CrearTrabajadorRequest req) {
        return trabajadorService.crear(req.usuarioId(), req.rut(), req.cuadrillaId());
    }

    @GetMapping("/{id}")
    public Trabajador obtener(@PathVariable Long id) {
        return trabajadorService.obtener(id);
    }

    @GetMapping("/por-credencial/{credencialQr}")
    public Trabajador buscarPorCredencial(@PathVariable String credencialQr) {
        return trabajadorService.buscarPorCredencialQr(credencialQr);
    }

    @GetMapping
    public List<Trabajador> listar(
            @RequestParam(required = false) Long cuadrillaId,
            @RequestParam(required = false) Long obraId) {
        if (cuadrillaId != null) {
            return trabajadorService.listarPorCuadrilla(cuadrillaId);
        }
        if (obraId != null) {
            return trabajadorService.listarPorObra(obraId);
        }
        throw new IllegalArgumentException("Se requiere cuadrillaId u obraId");
    }

    @PutMapping("/{id}/credencial")
    public Trabajador renovarCredencial(@PathVariable Long id) {
        return trabajadorService.renovarCredencial(id);
    }

    public record CrearTrabajadorRequest(Long usuarioId, String rut, Long cuadrillaId) {
    }
}
