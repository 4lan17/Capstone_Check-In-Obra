package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** Partida "1" *-- "N" ItemCubicado — resultado de MotorCubicacion.calcular(). */
@Entity
@Table(name = "items_cubicados")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ItemCubicado implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "cantidad_calculada", nullable = false)
    private double cantidadCalculada;

    @Column(name = "cantidad_con_merma", nullable = false)
    private double cantidadConMerma;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "partida_id", nullable = false)
    private Partida partida;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "material_id", nullable = false)
    private Material material;

    @Override
    public Long empresaId() {
        return partida.empresaId();
    }
}
