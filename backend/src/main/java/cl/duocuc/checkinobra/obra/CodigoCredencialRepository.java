package cl.duocuc.checkinobra.obra;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface CodigoCredencialRepository extends JpaRepository<CodigoCredencial, Long> {

    Optional<CodigoCredencial> findByCodigo(String codigo);

    List<CodigoCredencial> findByTrabajadorId(Long trabajadorId);

    boolean existsByCodigo(String codigo);

    /** Revoca todos los códigos del trabajador, vigentes o no. Devuelve cuántos borró. */
    @Modifying
    @Query("DELETE FROM CodigoCredencial c WHERE c.trabajador.id = :trabajadorId")
    int borrarDelTrabajador(@Param("trabajadorId") Long trabajadorId);
}
