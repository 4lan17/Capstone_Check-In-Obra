package cl.duocuc.checkinobra.cubicacion;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ItemCubicadoRepository extends JpaRepository<ItemCubicado, Long> {
    List<ItemCubicado> findByPartidaId(Long partidaId);
    void deleteByPartidaId(Long partidaId);
}
