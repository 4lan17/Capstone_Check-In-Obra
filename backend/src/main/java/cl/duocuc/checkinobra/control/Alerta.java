package cl.duocuc.checkinobra.control;

import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import cl.duocuc.checkinobra.inventario.PrestamoHerramienta;
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

import java.time.LocalDateTime;

/**
 * Alerta — PrestamoHerramienta "1" -- "0..N" Alerta en el diagrama, pero
 * solo el tipo NO_DEVUELTA nace de un préstamo; STOCK_CRITICO y
 * CIERRE_TURNO no tienen préstamo asociado. Por eso {@link #prestamoHerramienta}
 * es opcional. Se agrega además {@link #obra} (no está explícita en el
 * diagrama) porque los tres tipos de alerta se muestran siempre acotados
 * a una obra en las pantallas ya diseñadas — sin ese dato la alerta no es
 * accionable.
 */
@Entity
@Table(name = "alertas")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Alerta implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private TipoAlerta tipo;

    @Column(nullable = false)
    private String mensaje;

    @Column(nullable = false)
    private LocalDateTime fecha;

    @Column(nullable = false)
    private boolean resuelto;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "obra_id", nullable = false)
    private Obra obra;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "prestamo_herramienta_id")
    private PrestamoHerramienta prestamoHerramienta;

    /** Alerta.generar() del diagrama — fábrica estática. */
    public static Alerta generar(TipoAlerta tipo, String mensaje, Obra obra, PrestamoHerramienta prestamo) {
        return Alerta.builder()
                .tipo(tipo)
                .mensaje(mensaje)
                .obra(obra)
                .prestamoHerramienta(prestamo)
                .fecha(LocalDateTime.now())
                .resuelto(false)
                .build();
    }

    /** Alerta.resolver() del diagrama. */
    public void resolver() {
        if (this.resuelto) {
            throw new IllegalStateException("La alerta ya estaba resuelta");
        }
        this.resuelto = true;
    }

    @Override
    public Long empresaId() {
        return obra.empresaId();
    }
}
