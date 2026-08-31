package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.SesionActual;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
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
    public HerramientaResponse crear(@RequestBody CrearHerramientaRequest req) {
        // La empresa sale del token, no de la petición. Mientras el cliente
        // pudiera nombrarla, pedir los datos de otra constructora era cuestión
        // de cambiar un número en la URL.
        return HerramientaResponse.de(herramientaService.crear(
                SesionActual.empresaId(), req.codigoQr(), req.nombre(), req.categoria(), req.valorReposicion()));
    }

    @GetMapping
    public List<HerramientaResponse> listarPorEmpresa() {
        return herramientaService.listarPorEmpresa(SesionActual.empresaId()).stream()
                .map(HerramientaResponse::de)
                .toList();
    }

    @GetMapping("/{id}")
    public HerramientaResponse obtener(@PathVariable Long id) {
        return HerramientaResponse.de(herramientaService.obtener(id));
    }

    @GetMapping("/por-codigo/{codigoQr}")
    public HerramientaResponse buscarPorCodigo(@PathVariable String codigoQr) {
        return HerramientaResponse.de(herramientaService.buscarPorCodigoQr(codigoQr));
    }

    public record CrearHerramientaRequest(
            String codigoQr, String nombre, String categoria, double valorReposicion) {
    }
}
