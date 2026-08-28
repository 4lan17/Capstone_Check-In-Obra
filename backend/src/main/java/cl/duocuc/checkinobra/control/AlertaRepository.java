package cl.duocuc.checkinobra.control;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AlertaRepository extends JpaRepository<Alerta, Long> {
    List<Alerta> findByObraId(Long obraId);
    List<Alerta> findByObraIdAndResueltoFalse(Long obraId);
}
