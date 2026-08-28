package cl.duocuc.checkinobra.cubicacion;

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
    public Material crear(@RequestBody CrearMaterialRequest req) {
        return materialService.crear(
                req.empresaId(), req.sku(), req.nombre(), req.categoria(), req.precioUnitario(), req.stockMinimo());
    }

    @GetMapping
    public List<Material> listar(
            @RequestParam Long empresaId, @RequestParam(required = false) CategoriaMaterial categoria) {
        return categoria == null
                ? materialService.listarPorEmpresa(empresaId)
                : materialService.listarPorEmpresaYCategoria(empresaId, categoria);
    }

    @GetMapping("/{id}")
    public Material obtener(@PathVariable Long id) {
        return materialService.obtener(id);
    }

    @PutMapping("/{id}/precio")
    @PreAuthorize("hasRole('ADMIN')")
    public Material actualizarPrecio(@PathVariable Long id, @RequestBody ActualizarPrecioRequest req) {
        return materialService.actualizarPrecio(id, req.nuevoPrecio());
    }

    public record CrearMaterialRequest(
            Long empresaId, String sku, String nombre, CategoriaMaterial categoria,
            double precioUnitario, double stockMinimo) {
    }

    public record ActualizarPrecioRequest(double nuevoPrecio) {
    }
}
