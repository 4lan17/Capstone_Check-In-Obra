package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

@Service
@Transactional
public class ParametroMermaService {

    private final ParametroMermaRepository parametroMermaRepository;
    private final MaterialService materialService;

    public ParametroMermaService(ParametroMermaRepository parametroMermaRepository, MaterialService materialService) {
        this.parametroMermaRepository = parametroMermaRepository;
        this.materialService = materialService;
    }

    /** Crea o reemplaza la excepción de merma de un material puntual. */
    public ParametroMerma definirParaMaterial(Long materialId, double porcentaje) {
        materialService.obtener(materialId);
        Material material = materialService.obtener(materialId);
        ParametroMerma parametro = parametroMermaRepository.findByMaterialId(materialId)
                .orElseGet(() -> ParametroMerma.builder().material(material).build());
        parametro.setPorcentaje(porcentaje);
        return parametroMermaRepository.save(parametro);
    }

    @Transactional(readOnly = true)
    public Optional<ParametroMerma> paraMaterial(Long materialId) {
        materialService.obtener(materialId);
        return parametroMermaRepository.findByMaterialId(materialId);
    }
}
