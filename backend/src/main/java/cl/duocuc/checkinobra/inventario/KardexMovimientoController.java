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
    public KardexMovimientoResponse registrar(@RequestBody RegistrarMovimientoRequest req) {
        return KardexMovimientoResponse.de(kardexMovimientoService.registrarMovimiento(
                req.obraId(),
                req.materialId(),
                req.usuarioId(),
                req.trabajadorId(),
                req.tipo(),
                req.cantidad()));
    }

    /** El movimiento de bodega lo consulta quien lo administra o lo controla, no el trabajador. */
    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<KardexMovimientoResponse> listarPorObra(@RequestParam Long obraId) {
        return kardexMovimientoService.listarPorObra(obraId).stream().map(KardexMovimientoResponse::de).toList();
    }

    @GetMapping("/stock")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public double stockActual(@RequestParam Long obraId, @RequestParam Long materialId) {
        return kardexMovimientoService.stockActual(obraId, materialId);
    }

    public record RegistrarMovimientoRequest(
            Long obraId,
            Long materialId,
            Long usuarioId,
            /** A quién se le entrega. Obligatorio en un DESPACHO. */
            Long trabajadorId,
            TipoMovimiento tipo,
            double cantidad) {
    }
}
