package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;
import java.util.UUID;

@Service
@Transactional
public class TrabajadorService {

    private final TrabajadorRepository trabajadorRepository;
    private final UsuarioRepository usuarioRepository;
    private final CuadrillaService cuadrillaService;

    public TrabajadorService(
            TrabajadorRepository trabajadorRepository,
            UsuarioRepository usuarioRepository,
            CuadrillaService cuadrillaService) {
        this.trabajadorRepository = trabajadorRepository;
        this.usuarioRepository = usuarioRepository;
        this.cuadrillaService = cuadrillaService;
    }

    public Trabajador crear(Long usuarioId, String rut, Long cuadrillaId) {
        Usuario usuario = usuarioRepository.findById(usuarioId)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + usuarioId));
        if (usuario.getRol() != RolUsuario.TRABAJADOR) {
            throw new IllegalStateException("Solo un Usuario con rol TRABAJADOR puede extenderse a Trabajador");
        }
        Cuadrilla cuadrilla = cuadrillaId != null ? cuadrillaService.obtener(cuadrillaId) : null;
        Trabajador trabajador = Trabajador.builder()
                .rut(rut)
                .usuario(usuario)
                .cuadrilla(cuadrilla)
                .credencialQr(UUID.randomUUID().toString())
                .build();
        return trabajadorRepository.save(trabajador);
    }

    @Transactional(readOnly = true)
    public Trabajador obtener(Long id) {
        return trabajadorRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Trabajador no encontrado: " + id));
    }

    @Transactional(readOnly = true)
    public Trabajador buscarPorCredencialQr(String credencialQr) {
        return trabajadorRepository.findByCredencialQr(credencialQr)
                .orElseThrow(() -> new NoSuchElementException("Credencial no reconocida"));
    }

    @Transactional(readOnly = true)
    public List<Trabajador> listarPorCuadrilla(Long cuadrillaId) {
        return trabajadorRepository.findByCuadrillaId(cuadrillaId);
    }

    @Transactional(readOnly = true)
    public List<Trabajador> listarPorObra(Long obraId) {
        return trabajadorRepository.findByCuadrilla_ObraId(obraId);
    }

    /** Renueva el QR de la credencial (pantalla TrabCredencial · "Renovar código"). */
    public Trabajador renovarCredencial(Long trabajadorId) {
        Trabajador trabajador = obtener(trabajadorId);
        trabajador.setCredencialQr(UUID.randomUUID().toString());
        return trabajadorRepository.save(trabajador);
    }
}
