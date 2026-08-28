package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class KardexMovimientoService {

    private final KardexMovimientoRepository kardexMovimientoRepository;
    private final ObraService obraService;
    private final MaterialService materialService;
    private final UsuarioRepository usuarioRepository;

    public KardexMovimientoService(
            KardexMovimientoRepository kardexMovimientoRepository,
            ObraService obraService,
            MaterialService materialService,
            UsuarioRepository usuarioRepository) {
        this.kardexMovimientoRepository = kardexMovimientoRepository;
        this.obraService = obraService;
        this.materialService = materialService;
        this.usuarioRepository = usuarioRepository;
    }

    /**
     * KardexMovimiento.registrar() del diagrama, orquestado: valida que
     * un DESPACHO o CONSUMO no deje el stock de la obra en negativo — el
     * mismo bloqueo que ya anticipaba la pantalla de despacho.
     */
    public KardexMovimiento registrarMovimiento(
            Long obraId, Long materialId, Long usuarioId, TipoMovimiento tipo, double cantidad) {
        Obra obra = obraService.obtener(obraId);
        Material material = materialService.obtener(materialId);
        Usuario usuario = usuarioRepository.findById(usuarioId)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + usuarioId));

        if (tipo != TipoMovimiento.RECEPCION) {
            double stockActual = stockActual(obraId, materialId);
            if (cantidad > stockActual) {
                throw new IllegalStateException(
                        "Stock insuficiente: quedan " + stockActual + " y se pidieron " + cantidad);
            }
        }

        KardexMovimiento movimiento = KardexMovimiento.builder()
                .obra(obra)
                .material(material)
                .usuario(usuario)
                .tipoMovimiento(tipo)
                .cantidad(cantidad)
                .fecha(LocalDateTime.now())
                .build();
        movimiento.registrar();
        return kardexMovimientoRepository.save(movimiento);
    }

    /** Stock actual = suma con signo de los movimientos de ese material en esa obra. */
    @Transactional(readOnly = true)
    public double stockActual(Long obraId, Long materialId) {
        return kardexMovimientoRepository.findByObraIdAndMaterialId(obraId, materialId).stream()
                .mapToDouble(m -> m.getCantidad() * m.signo())
                .sum();
    }

    @Transactional(readOnly = true)
    public List<KardexMovimiento> listarPorObra(Long obraId) {
        return kardexMovimientoRepository.findByObraId(obraId);
    }
}
