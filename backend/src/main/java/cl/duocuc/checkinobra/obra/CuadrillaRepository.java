package cl.duocuc.checkinobra.obra;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface CuadrillaRepository extends JpaRepository<Cuadrilla, Long> {
    List<Cuadrilla> findByObraId(Long obraId);
}
