package cl.duocuc.checkinobra.obra;

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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/obras")
@Tag(name = "Obra")
public class ObraController {

    private final ObraService obraService;

    public ObraController(ObraService obraService) {
        this.obraService = obraService;
    }

    /** Crear y cerrar obras es exclusivo de ADMIN, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    @ResponseStatus(HttpStatus.CREATED)
    public ObraResponse crear(@RequestBody CrearObraRequest req) {
        // La empresa sale del token, no de la petición. Mientras el cliente
        // pudiera nombrarla, pedir los datos de otra constructora era cuestión
        // de cambiar un número en la URL.
        return ObraResponse.de(obraService.crear(
                SesionActual.empresaId(), req.nombre(), req.cliente(), req.ubicacion(), req.jefeTerrenoId()));
    }

    @GetMapping
    public List<ObraResponse> listarPorEmpresa() {
        return obraService.listarPorEmpresa(SesionActual.empresaId()).stream().map(ObraResponse::de).toList();
    }

    @GetMapping("/{id}")
    public ObraResponse obtener(@PathVariable Long id) {
        return ObraResponse.de(obraService.obtener(id));
    }

    /** Asignar o cambiar el jefe a cargo. */
    @PutMapping("/{id}/jefe-terreno")
    @PreAuthorize("hasRole('ADMIN')")
    public ObraResponse asignarJefe(@PathVariable Long id, @RequestBody AsignarJefeRequest req) {
        return ObraResponse.de(obraService.asignarJefeDeTerreno(id, req.jefeTerrenoId()));
    }

    @PutMapping("/{id}/cerrar")
    @PreAuthorize("hasRole('ADMIN')")
    public ObraResponse cerrar(@PathVariable Long id) {
        return ObraResponse.de(obraService.cerrarObra(id));
    }

    public record CrearObraRequest(String nombre, String cliente, String ubicacion, Long jefeTerrenoId) {
    }

    public record AsignarJefeRequest(Long jefeTerrenoId) {
    }
}
