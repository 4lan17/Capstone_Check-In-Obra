package cl.duocuc.checkinobra.cubicacion;

import io.swagger.v3.oas.annotations.Operation;
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
@RequestMapping("/api/partidas")
@Tag(name = "Partida y cubicación")
public class PartidaController {

    private final PartidaService partidaService;
    private final MotorCubicacionService motorCubicacionService;

    public PartidaController(PartidaService partidaService, MotorCubicacionService motorCubicacionService) {
        this.partidaService = partidaService;
        this.motorCubicacionService = motorCubicacionService;
    }

    /** Cubicar una partida es de JEFE_TERRENO o ADMIN, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    @ResponseStatus(HttpStatus.CREATED)
    public PartidaResponse crear(@RequestBody CrearPartidaRequest req) {
        return PartidaResponse.de(
                partidaService.crear(req.obraId(), req.tipo(), req.anchoM(), req.altoM(), req.separacionMontantes()));
    }

    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<PartidaResponse> listarPorObra(@RequestParam Long obraId) {
        return partidaService.listarPorObra(obraId).stream().map(PartidaResponse::de).toList();
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public PartidaResponse obtener(@PathVariable Long id) {
        return PartidaResponse.de(partidaService.obtener(id));
    }

    @PostMapping("/{id}/cubicar")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    @Operation(summary = "MotorCubicacion.calcular(p): List<ItemCubicado>")
    public List<ItemCubicadoResponse> cubicar(@PathVariable Long id) {
        return motorCubicacionService.calcular(id).stream().map(ItemCubicadoResponse::de).toList();
    }

    @GetMapping("/{id}/items-cubicados")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<ItemCubicadoResponse> itemsCubicados(@PathVariable Long id) {
        return partidaService.itemsCubicados(id).stream().map(ItemCubicadoResponse::de).toList();
    }

    public record CrearPartidaRequest(
            Long obraId, TipoPartida tipo, double anchoM, double altoM, double separacionMontantes) {
    }
}
