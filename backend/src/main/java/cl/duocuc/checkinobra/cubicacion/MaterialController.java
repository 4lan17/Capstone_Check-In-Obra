package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.SesionActual;
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
@RequestMapping("/api/materiales")
@Tag(name = "Material")
public class MaterialController {

    private final MaterialService materialService;

    public MaterialController(MaterialService materialService) {
        this.materialService = materialService;
    }

    /** Definir catálogo y precios es exclusivo de ADMIN, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    @ResponseStatus(HttpStatus.CREATED)
    public MaterialResponse crear(@RequestBody CrearMaterialRequest req) {
        // La empresa sale del token, no de la petición. Mientras el cliente
        // pudiera nombrarla, pedir los datos de otra constructora era cuestión
        // de cambiar un número en la URL.
        return MaterialResponse.de(materialService.crear(
                SesionActual.empresaId(),
                req.sku(),
                req.nombre(),
                req.categoria(),
                req.precioUnitario(),
                req.stockMinimo()));
    }

    @GetMapping
    public List<MaterialResponse> listar(@RequestParam(required = false) CategoriaMaterial categoria) {
        Long empresaId = SesionActual.empresaId();
        List<Material> materiales = categoria == null
                ? materialService.listarPorEmpresa(empresaId)
                : materialService.listarPorEmpresaYCategoria(empresaId, categoria);
        return materiales.stream().map(MaterialResponse::de).toList();
    }

    @GetMapping("/{id}")
    public MaterialResponse obtener(@PathVariable Long id) {
        return MaterialResponse.de(materialService.obtener(id));
    }

    @PutMapping("/{id}/precio")
    @PreAuthorize("hasRole('ADMIN')")
    public MaterialResponse actualizarPrecio(@PathVariable Long id, @RequestBody ActualizarPrecioRequest req) {
        return MaterialResponse.de(materialService.actualizarPrecio(id, req.nuevoPrecio()));
    }

    public record CrearMaterialRequest(
            String sku, String nombre, CategoriaMaterial categoria, double precioUnitario, double stockMinimo) {
    }

    public record ActualizarPrecioRequest(double nuevoPrecio) {
    }
}
