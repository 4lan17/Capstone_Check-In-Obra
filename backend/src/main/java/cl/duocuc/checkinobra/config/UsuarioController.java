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
import org.springframework.web.bind.annotation.RequestParam;
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
    public Usuario crear(@RequestBody CrearUsuarioRequest req) {
        return usuarioService.crear(req.empresaId(), req.nombre(), req.email(), req.rol(), req.pinInicial());
    }

    @GetMapping
    public List<Usuario> listarPorEmpresa(@RequestParam Long empresaId) {
        return usuarioService.listarPorEmpresa(empresaId);
    }

    @GetMapping("/{id}")
    public Usuario obtener(@PathVariable Long id) {
        return usuarioService.obtener(id);
    }

    @PutMapping("/{id}/pin")
    @PreAuthorize("hasRole('ADMIN')")
    public Usuario redefinirPin(@PathVariable Long id, @RequestBody RedefinirPinRequest req) {
        return usuarioService.redefinirPin(id, req.nuevoPin());
    }

    public record CrearUsuarioRequest(
            Long empresaId, String nombre, String email, RolUsuario rol, String pinInicial) {
    }

    public record RedefinirPinRequest(String nuevoPin) {
    }
}
