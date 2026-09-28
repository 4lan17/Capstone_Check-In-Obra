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
    public Usuario crear(
            Long empresaId, String nombre, String email, String rut, RolUsuario rol, String pinInicial) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        if (usuarioRepository.existsByEmail(email)) {
            throw new IllegalStateException("Ya existe un usuario con ese correo");
        }
        // El RUT identifica a la persona en toda la cadena: quien recibe un
        // despacho, quien tiene una herramienta y quien dirige la obra se
        // muestran por nombre y RUT.
        //
        // Se normaliza antes de comparar: "14109556-0" y "14.109.556-0" son la
        // misma persona, y el UNIQUE de la columna solo lo ve si llegan escritos
        // igual.
        rut = Rut.normalizar(rut);
        if (usuarioRepository.existsByRut(rut)) {
            throw new IllegalStateException("Ya existe un usuario con ese RUT");
        }
        Empresa empresa = empresaService.obtener(empresaId);
        Usuario usuario = Usuario.builder()
                .nombre(nombre)
                .email(email)
                .rut(rut)
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
        AccesoEmpresa.exigirEmpresa(empresaId);
        return usuarioRepository.findByEmpresaId(empresaId);
    }

    @Transactional(readOnly = true)
    public List<Usuario> listarPorEmpresaYRol(Long empresaId, RolUsuario rol) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        return usuarioRepository.findByEmpresaIdAndRol(empresaId, rol);
    }

    @Transactional(readOnly = true)
    public Usuario obtener(Long id) {
        return usuarioRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + id));
    }

    public Usuario redefinirPin(Long usuarioId, String nuevoPin) {
        Usuario usuario = obtener(usuarioId);
        usuario.definirPin(nuevoPin);
        return usuarioRepository.save(usuario);
    }
}
