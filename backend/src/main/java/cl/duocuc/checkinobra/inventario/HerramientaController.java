package cl.duocuc.checkinobra.inventario;

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
@RequestMapping("/api/herramientas")
@Tag(name = "Herramienta")
public class HerramientaController {

    private final HerramientaService herramientaService;

    public HerramientaController(HerramientaService herramientaService) {
        this.herramientaService = herramientaService;
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    @ResponseStatus(HttpStatus.CREATED)
    public Herramienta crear(@RequestBody CrearHerramientaRequest req) {
        return herramientaService.crear(
                req.empresaId(), req.codigoQr(), req.nombre(), req.categoria(), req.valorReposicion());
    }

    @GetMapping
    public List<Herramienta> listarPorEmpresa(@RequestParam Long empresaId) {
        return herramientaService.listarPorEmpresa(empresaId);
    }

    @GetMapping("/{id}")
    public Herramienta obtener(@PathVariable Long id) {
        return herramientaService.obtener(id);
    }

    @GetMapping("/por-codigo/{codigoQr}")
    public Herramienta buscarPorCodigo(@PathVariable String codigoQr) {
        return herramientaService.buscarPorCodigoQr(codigoQr);
    }

    public record CrearHerramientaRequest(
            Long empresaId, String codigoQr, String nombre, String categoria, double valorReposicion) {
    }
}
