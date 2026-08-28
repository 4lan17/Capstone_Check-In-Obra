package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.obra.Trabajador;
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
 * SolicitudHerramienta — la crea el Trabajador, la aprueba/rechaza el
 * Bodeguero (o Admin); recién al aprobar se genera un PrestamoHerramienta
 * (orquestado por SolicitudHerramientaService.aprobar(), porque construir
 * el préstamo necesita la Obra, que se deriva de trabajador.cuadrilla.obra).
 */
@Entity
@Table(name = "solicitudes_herramienta")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SolicitudHerramienta {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private int cantidad;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoSolicitud estado;

    @Column(name = "fecha_solicitud", nullable = false)
    private LocalDateTime fechaSolicitud;

    /**
     * Motivo de rechazo — no está en el diagrama de clases, se agrega
     * porque la pantalla de rechazo del bodeguero (BodRechazo) lo exige
     * como dato obligatorio para que el trabajador entienda por qué.
     */
    @Column(name = "motivo_rechazo")
    private String motivoRechazo;

    /** Trabajador "1" -- "N" SolicitudHerramienta : solicita > */
    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "trabajador_id", nullable = false)
    private Trabajador trabajador;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "herramienta_id", nullable = false)
    private Herramienta herramienta;

    /** Usuario "1" -- "N" SolicitudHerramienta : aprueba/rechaza > */
    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "resuelto_por_id")
    private Usuario resueltoPor;

    /**
     * SolicitudHerramienta.aprobar(): PrestamoHerramienta del diagrama.
     * Transición pura de estado; el PrestamoHerramienta lo construye y
     * persiste el servicio inmediatamente después.
     */
    public void aprobar(Usuario aprobador) {
        exigirPendiente();
        this.estado = EstadoSolicitud.APROBADA;
        this.resueltoPor = aprobador;
    }

    /** SolicitudHerramienta.rechazar() del diagrama. */
    public void rechazar(Usuario rechazador, String motivo) {
        exigirPendiente();
        this.estado = EstadoSolicitud.RECHAZADA;
        this.resueltoPor = rechazador;
        this.motivoRechazo = motivo;
    }

    private void exigirPendiente() {
        if (this.estado != EstadoSolicitud.PENDIENTE) {
            throw new IllegalStateException("La solicitud ya fue resuelta (estado actual: " + estado + ")");
        }
    }
}
