package cl.duocuc.checkinobra.obra;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class CuadrillaService {

    private final CuadrillaRepository cuadrillaRepository;
    private final ObraService obraService;

    public CuadrillaService(CuadrillaRepository cuadrillaRepository, ObraService obraService) {
        this.cuadrillaRepository = cuadrillaRepository;
        this.obraService = obraService;
    }

    public Cuadrilla crear(Long obraId, String nombre) {
        Obra obra = obraService.obtener(obraId);
        return cuadrillaRepository.save(Cuadrilla.builder().nombre(nombre).obra(obra).build());
    }

    @Transactional(readOnly = true)
    public List<Cuadrilla> listarPorObra(Long obraId) {
        return cuadrillaRepository.findByObraId(obraId);
    }

    @Transactional(readOnly = true)
    public Cuadrilla obtener(Long id) {
        return cuadrillaRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Cuadrilla no encontrada: " + id));
    }
}
