package cl.duocuc.checkinobra.inventario;

import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/kardex")
@Tag(name = "Kardex")
public class KardexMovimientoController {

    private final KardexMovimientoService kardexMovimientoService;

    public KardexMovimientoController(KardexMovimientoService kardexMovimientoService) {
        this.kardexMovimientoService = kardexMovimientoService;
    }

    /** Recepción, despacho y consumo son de BODEGUERO o ADMIN, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    @ResponseStatus(HttpStatus.CREATED)
    public KardexMovimiento registrar(@RequestBody RegistrarMovimientoRequest req) {
        return kardexMovimientoService.registrarMovimiento(
                req.obraId(), req.materialId(), req.usuarioId(), req.tipo(), req.cantidad());
    }

    @GetMapping
    public List<KardexMovimiento> listarPorObra(@RequestParam Long obraId) {
        return kardexMovimientoService.listarPorObra(obraId);
    }

    @GetMapping("/stock")
    public double stockActual(@RequestParam Long obraId, @RequestParam Long materialId) {
        return kardexMovimientoService.stockActual(obraId, materialId);
    }

    public record RegistrarMovimientoRequest(
            Long obraId, Long materialId, Long usuarioId, TipoMovimiento tipo, double cantidad) {
    }
}
