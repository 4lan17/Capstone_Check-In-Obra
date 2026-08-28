package cl.duocuc.checkinobra.cubicacion;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PartidaRepository extends JpaRepository<Partida, Long> {
    List<Partida> findByObraId(Long obraId);
}
