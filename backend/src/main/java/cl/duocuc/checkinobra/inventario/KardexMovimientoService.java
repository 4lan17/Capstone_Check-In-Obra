package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.obra.TrabajadorService;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.config.AccesoEmpresa;
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
    private final TrabajadorService trabajadorService;

    public KardexMovimientoService(
            KardexMovimientoRepository kardexMovimientoRepository,
            ObraService obraService,
            MaterialService materialService,
            UsuarioRepository usuarioRepository,
            TrabajadorService trabajadorService) {
        this.kardexMovimientoRepository = kardexMovimientoRepository;
        this.obraService = obraService;
        this.materialService = materialService;
        this.usuarioRepository = usuarioRepository;
        this.trabajadorService = trabajadorService;
    }

    /**
     * KardexMovimiento.registrar() del diagrama, orquestado: valida que
     * un DESPACHO o CONSUMO no deje el stock de la obra en negativo — el
     * mismo bloqueo que ya anticipaba la pantalla de despacho.
     */
    public KardexMovimiento registrarMovimiento(
            Long obraId,
            Long materialId,
            Long usuarioId,
            Long trabajadorId,
            TipoMovimiento tipo,
            double cantidad) {
        Obra obra = obraService.obtener(obraId);
        Material material = materialService.obtener(materialId);
        Usuario usuario = usuarioRepository.findById(usuarioId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + usuarioId));

        Trabajador receptor = resolverReceptor(tipo, trabajadorId);

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
                .trabajador(receptor)
                .tipoMovimiento(tipo)
                .cantidad(cantidad)
                .fecha(LocalDateTime.now())
                .build();
        movimiento.registrar();
        return kardexMovimientoRepository.save(movimiento);
    }

    /**
     * Quién se lleva el material.
     *
     * <p>Un DESPACHO sin receptor deja el kardex sin poder responder "¿a quién se
     * le entregaron esas 36 planchas?", que es justo lo que el bodeguero necesita
     * cuando aparece un descuadre. Un CONSUMO puede no tenerlo —es material que
     * se gastó en la obra, no que alguien se llevó— y una RECEPCION nunca lo
     * tiene, porque el material entra desde un proveedor.
     */
    private Trabajador resolverReceptor(TipoMovimiento tipo, Long trabajadorId) {
        if (tipo == TipoMovimiento.RECEPCION) {
            if (trabajadorId != null) {
                throw new IllegalArgumentException(
                        "Una recepción no tiene trabajador receptor: el material entra desde un proveedor");
            }
            return null;
        }
        if (tipo == TipoMovimiento.DESPACHO && trabajadorId == null) {
            throw new IllegalArgumentException("Un despacho debe indicar a qué trabajador se le entrega");
        }
        return trabajadorId == null ? null : trabajadorService.obtener(trabajadorId);
    }

    /** Stock actual = suma con signo de los movimientos de ese material en esa obra. */
    @Transactional(readOnly = true)
    public double stockActual(Long obraId, Long materialId) {
        obraService.obtener(obraId);
        return kardexMovimientoRepository.findByObraIdAndMaterialId(obraId, materialId).stream()
                .mapToDouble(m -> m.getCantidad() * m.signo())
                .sum();
    }

    @Transactional(readOnly = true)
    public List<KardexMovimiento> listarPorObra(Long obraId) {
        obraService.obtener(obraId);
        return kardexMovimientoRepository.findByObraId(obraId);
    }
}
