package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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

/** Material "1" -- "0..1" ParametroMerma — no todo material tiene excepción propia. */
@Entity
@Table(name = "parametros_merma")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ParametroMerma implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Porcentaje expresado en base 100 (12.0 = 12 %). */
    @Column(nullable = false)
    private double porcentaje;

    @OneToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "material_id", nullable = false, unique = true)
    private Material material;

    /** ParametroMerma.aplicar(cantidad): float del diagrama. */
    public double aplicar(double cantidad) {
        return cantidad * (1 + porcentaje / 100.0);
    }

    @Override
    public Long empresaId() {
        return material.empresaId();
    }
}
