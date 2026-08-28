package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.obra.TrabajadorService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class PrestamoHerramientaService {

    private final PrestamoHerramientaRepository prestamoHerramientaRepository;
    private final HerramientaRepository herramientaRepository;
    private final TrabajadorService trabajadorService;
    private final ObraService obraService;
    private final UsuarioRepository usuarioRepository;

    public PrestamoHerramientaService(
            PrestamoHerramientaRepository prestamoHerramientaRepository,
            HerramientaRepository herramientaRepository,
            TrabajadorService trabajadorService,
            ObraService obraService,
            UsuarioRepository usuarioRepository) {
        this.prestamoHerramientaRepository = prestamoHerramientaRepository;
        this.herramientaRepository = herramientaRepository;
        this.trabajadorService = trabajadorService;
        this.obraService = obraService;
        this.usuarioRepository = usuarioRepository;
    }

    /**
     * Préstamo directo del bodeguero, sin pasar por una SolicitudHerramienta
     * (la otra vía es SolicitudHerramientaService.aprobar()).
     */
    public PrestamoHerramienta prestarDirecto(
            Long herramientaId, Long trabajadorId, Long obraId, Long autorizadorId, LocalDateTime fechaDevolEsperada) {
        Herramienta herramienta = herramientaRepository.findById(herramientaId)
                .orElseThrow(() -> new NoSuchElementException("Herramienta no encontrada: " + herramientaId));
        if (herramienta.getEstado() != EstadoHerramienta.DISPONIBLE) {
            throw new IllegalStateException("La herramienta no está DISPONIBLE (estado actual: " + herramienta.getEstado() + ")");
        }
        Trabajador trabajador = trabajadorService.obtener(trabajadorId);
        Obra obra = obraService.obtener(obraId);
        Usuario autorizador = usuarioRepository.findById(autorizadorId)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + autorizadorId));

        PrestamoHerramienta prestamo = PrestamoHerramienta.builder()
                .herramienta(herramienta)
                .trabajador(trabajador)
                .obra(obra)
                .autorizadoPor(autorizador)
                .fechaDevolEsperada(fechaDevolEsperada)
                .build();
        prestamo.autorizar();

        herramienta.setEstado(EstadoHerramienta.PRESTADA);
        herramientaRepository.save(herramienta);
        return prestamoHerramientaRepository.save(prestamo);
    }

    /**
     * PrestamoHerramienta.registrarDevolucion() del diagrama, orquestado:
     * también decide el nuevo EstadoHerramienta (DISPONIBLE o MANTENCION).
     */
    public PrestamoHerramienta registrarDevolucion(Long prestamoId, EstadoHerramienta nuevoEstadoHerramienta) {
        if (nuevoEstadoHerramienta == EstadoHerramienta.PRESTADA) {
            throw new IllegalArgumentException("El estado de devolución no puede ser PRESTADA");
        }
        PrestamoHerramienta prestamo = obtener(prestamoId);
        prestamo.registrarDevolucion();

        Herramienta herramienta = prestamo.getHerramienta();
        herramienta.setEstado(nuevoEstadoHerramienta);
        herramientaRepository.save(herramienta);

        return prestamoHerramientaRepository.save(prestamo);
    }

    @Transactional(readOnly = true)
    public PrestamoHerramienta obtener(Long id) {
        return prestamoHerramientaRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Préstamo no encontrado: " + id));
    }

    @Transactional(readOnly = true)
    public List<PrestamoHerramienta> listarPorObra(Long obraId) {
        return prestamoHerramientaRepository.findByObraId(obraId);
    }

    @Transactional(readOnly = true)
    public List<PrestamoHerramienta> listarPorTrabajador(Long trabajadorId) {
        return prestamoHerramientaRepository.findByTrabajadorId(trabajadorId);
    }

    @Transactional(readOnly = true)
    public List<PrestamoHerramienta> listarVencidos() {
        return prestamoHerramientaRepository
                .findByFechaDevolRealIsNullAndFechaDevolEsperadaBefore(LocalDateTime.now());
    }
}
