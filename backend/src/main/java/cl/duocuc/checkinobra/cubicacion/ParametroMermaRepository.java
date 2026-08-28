package cl.duocuc.checkinobra.cubicacion;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface ParametroMermaRepository extends JpaRepository<ParametroMerma, Long> {
    Optional<ParametroMerma> findByMaterialId(Long materialId);
}
