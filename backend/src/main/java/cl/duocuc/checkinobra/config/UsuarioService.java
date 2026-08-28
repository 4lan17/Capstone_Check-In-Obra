package cl.duocuc.checkinobra.config;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class UsuarioService {

    private final UsuarioRepository usuarioRepository;
    private final EmpresaService empresaService;

    public UsuarioService(UsuarioRepository usuarioRepository, EmpresaService empresaService) {
        this.usuarioRepository = usuarioRepository;
        this.empresaService = empresaService;
    }

    /** Corresponde a Empresa.registrarUsuario(u) del diagrama, orquestado desde el servicio. */
    public Usuario crear(Long empresaId, String nombre, String email, RolUsuario rol, String pinInicial) {
        if (usuarioRepository.existsByEmail(email)) {
            throw new IllegalStateException("Ya existe un usuario con ese correo");
        }
        Empresa empresa = empresaService.obtener(empresaId);
        Usuario usuario = Usuario.builder()
                .nombre(nombre)
                .email(email)
                .rol(rol)
                .build();
        empresa.registrarUsuario(usuario);
        if (pinInicial != null) {
            usuario.definirPin(pinInicial);
        }
        return usuarioRepository.save(usuario);
    }

    @Transactional(readOnly = true)
    public List<Usuario> listarPorEmpresa(Long empresaId) {
        return usuarioRepository.findByEmpresaId(empresaId);
    }

    @Transactional(readOnly = true)
    public List<Usuario> listarPorEmpresaYRol(Long empresaId, RolUsuario rol) {
        return usuarioRepository.findByEmpresaIdAndRol(empresaId, rol);
    }

    @Transactional(readOnly = true)
    public Usuario obtener(Long id) {
        return usuarioRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + id));
    }

    public Usuario redefinirPin(Long usuarioId, String nuevoPin) {
        Usuario usuario = obtener(usuarioId);
        usuario.definirPin(nuevoPin);
        return usuarioRepository.save(usuario);
    }
}
