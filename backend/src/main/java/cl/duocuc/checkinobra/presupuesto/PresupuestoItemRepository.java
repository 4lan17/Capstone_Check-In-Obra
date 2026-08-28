package cl.duocuc.checkinobra.presupuesto;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PresupuestoItemRepository extends JpaRepository<PresupuestoItem, Long> {
    List<PresupuestoItem> findByPresupuestoId(Long presupuestoId);
}
