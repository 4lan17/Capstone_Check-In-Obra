package cl.duocuc.checkinobra.config;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Empresa — raíz del multi-tenant del MVP1. Toda Obra, Usuario, Material y
 * Herramienta pertenece a exactamente una Empresa (Empresa "1" o-- "N" ...).
 */
@Entity
@Table(name = "empresas")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Empresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String nombre;

    @Column(nullable = false, unique = true)
    private String rut;

    /**
     * Empresa.registrarUsuario(u: Usuario) del diagrama de clases.
     * Vincula el usuario a esta empresa; la persistencia la hace el
     * servicio (UsuarioService) después de llamar este método.
     */
    public void registrarUsuario(Usuario u) {
        if (u == null) {
            throw new IllegalArgumentException("El usuario no puede ser nulo");
        }
        u.setEmpresa(this);
    }
}
