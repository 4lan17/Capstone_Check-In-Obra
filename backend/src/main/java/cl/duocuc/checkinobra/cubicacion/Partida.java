package cl.duocuc.checkinobra.cubicacion;

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
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** Obra "1" *-- "N" Partida — no existe partida sin obra. */
@Entity
@Table(name = "partidas")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Partida {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private TipoPartida tipo;

    @Column(name = "ancho_m", nullable = false)
    private double anchoM;

    @Column(name = "alto_m", nullable = false)
    private double altoM;

    @Column(name = "separacion_montantes", nullable = false)
    private double separacionMontantes;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "obra_id", nullable = false)
    private Obra obra;

    /** Superficie neta en m² — base de MotorCubicacion.calcular(). */
    public double superficieM2() {
        return anchoM * altoM;
    }
}
