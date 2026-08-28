package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class PartidaService {

    private final PartidaRepository partidaRepository;
    private final ItemCubicadoRepository itemCubicadoRepository;
    private final ObraService obraService;

    public PartidaService(
            PartidaRepository partidaRepository,
            ItemCubicadoRepository itemCubicadoRepository,
            ObraService obraService) {
        this.partidaRepository = partidaRepository;
        this.itemCubicadoRepository = itemCubicadoRepository;
        this.obraService = obraService;
    }

    public Partida crear(Long obraId, TipoPartida tipo, double anchoM, double altoM, double separacionMontantes) {
        Obra obra = obraService.obtener(obraId);
        Partida partida = Partida.builder()
                .tipo(tipo)
                .anchoM(anchoM)
                .altoM(altoM)
                .separacionMontantes(separacionMontantes)
                .obra(obra)
                .build();
        return partidaRepository.save(partida);
    }

    @Transactional(readOnly = true)
    public List<Partida> listarPorObra(Long obraId) {
        return partidaRepository.findByObraId(obraId);
    }

    @Transactional(readOnly = true)
    public Partida obtener(Long id) {
        return partidaRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Partida no encontrada: " + id));
    }

    @Transactional(readOnly = true)
    public List<ItemCubicado> itemsCubicados(Long partidaId) {
        return itemCubicadoRepository.findByPartidaId(partidaId);
    }
}
