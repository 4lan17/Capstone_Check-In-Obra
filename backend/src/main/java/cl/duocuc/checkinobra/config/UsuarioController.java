package cl.duocuc.checkinobra.config;

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
@RequestMapping("/api/usuarios")
@Tag(name = "Usuario")
public class UsuarioController {

    private final UsuarioService usuarioService;

    public UsuarioController(UsuarioService usuarioService) {
        this.usuarioService = usuarioService;
    }

    /** Crear usuarios y asignar rol es exclusivo de ADMIN, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    @ResponseStatus(HttpStatus.CREATED)
    public UsuarioResponse crear(@RequestBody CrearUsuarioRequest req) {
        // La empresa sale del token, no de la petición. Mientras el cliente
        // pudiera nombrarla, pedir los datos de otra constructora era cuestión
        // de cambiar un número en la URL.
        return UsuarioResponse.de(usuarioService.crear(
                SesionActual.empresaId(), req.nombre(), req.email(), req.rut(), req.rol(), req.pinInicial()));
    }

    /** Leer el padrón es tan sensible como escribirlo: mismo rol que crear. */
    @GetMapping
    @PreAuthorize("hasRole('ADMIN')")
    public List<UsuarioResponse> listarPorEmpresa() {
        return usuarioService.listarPorEmpresa(SesionActual.empresaId()).stream()
                .map(UsuarioResponse::de)
                .toList();
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public UsuarioResponse obtener(@PathVariable Long id) {
        return UsuarioResponse.de(usuarioService.obtener(id));
    }

    @PutMapping("/{id}/pin")
    @PreAuthorize("hasRole('ADMIN')")
    public UsuarioResponse redefinirPin(@PathVariable Long id, @RequestBody RedefinirPinRequest req) {
        return UsuarioResponse.de(usuarioService.redefinirPin(id, req.nuevoPin()));
    }

    public record CrearUsuarioRequest(
            String nombre, String email, String rut, RolUsuario rol, String pinInicial) {
    }

    public record RedefinirPinRequest(String nuevoPin) {
    }
}
