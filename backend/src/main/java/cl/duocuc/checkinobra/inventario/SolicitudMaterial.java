package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.obra.Obra;
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
 * SolicitudMaterial — igual que SolicitudHerramienta pero al aprobar genera
 * un KardexMovimiento de DESPACHO en vez de un préstamo.
 */
@Entity
@Table(name = "solicitudes_material")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SolicitudMaterial implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private double cantidad;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoSolicitud estado;

    @Column(name = "fecha_solicitud", nullable = false)
    private LocalDateTime fechaSolicitud;

    /** Ver nota en SolicitudHerramienta.motivoRechazo — no está en el diagrama. */
    @Column(name = "motivo_rechazo")
    private String motivoRechazo;

    /** Trabajador "1" -- "N" SolicitudMaterial : solicita > */
    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "trabajador_id", nullable = false)
    private Trabajador trabajador;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "material_id", nullable = false)
    private Material material;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "obra_id", nullable = false)
    private Obra obra;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "resuelto_por_id")
    private Usuario resueltoPor;

    /** SolicitudMaterial.aprobar(): KardexMovimiento del diagrama. */
    public void aprobar(Usuario aprobador) {
        exigirPendiente();
        this.estado = EstadoSolicitud.APROBADA;
        this.resueltoPor = aprobador;
    }

    /** SolicitudMaterial.rechazar() del diagrama. */
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

    @Override
    public Long empresaId() {
        return obra.empresaId();
    }
}
