package cl.duocuc.checkinobra.presupuesto;

import cl.duocuc.checkinobra.obra.Obra;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDate;
import java.util.List;

/** Obra "1" *-- "0..1" Presupuesto — a lo más un presupuesto vigente por obra. */
@Entity
@Table(name = "presupuestos")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Presupuesto {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoPresupuesto estado;

    @Column(name = "fecha_congelado")
    private LocalDate fechaCongelado;

    @Column(nullable = false)
    private double total;

    @OneToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "obra_id", nullable = false, unique = true)
    private Obra obra;

    /**
     * Presupuesto.congelar() del diagrama. Solo se congela desde APROBADO;
     * congelado, los precios dejan de seguir al catálogo.
     */
    public void congelar() {
        if (this.estado != EstadoPresupuesto.APROBADO) {
            throw new IllegalStateException(
                    "Solo se puede congelar un presupuesto APROBADO (estado actual: " + estado + ")");
        }
        this.estado = EstadoPresupuesto.CONGELADO;
        this.fechaCongelado = LocalDate.now();
    }

    /**
     * Presupuesto.calcularTotal(): float del diagrama. Recibe los ítems en
     * vez de cargarlos desde una colección mapeada, para no acoplar la
     * entidad a Hibernate ni a ciclos de serialización JSON — el servicio
     * los trae desde PresupuestoItemRepository.
     */
    public double calcularTotal(List<PresupuestoItem> items) {
        double suma = items.stream().mapToDouble(PresupuestoItem::getSubtotal).sum();
        this.total = suma;
        return suma;
    }
}
