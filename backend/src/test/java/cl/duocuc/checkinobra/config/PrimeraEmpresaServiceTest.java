package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * MT1 (#104): la migración V2 ya no siembra la empresa ni su administrador. El
 * primero nace al arrancar una base vacía, con la clave que viene del entorno.
 */
@ExtendWith(MockitoExtension.class)
class PrimeraEmpresaServiceTest {

    @Mock private EmpresaRepository empresaRepository;
    @Mock private UsuarioRepository usuarioRepository;
    @InjectMocks private PrimeraEmpresaService servicio;

    @Test
    void enUnaBaseVaciaCreaLaEmpresaYSuAdminObligadoACambiarLaClave() {
        when(empresaRepository.count()).thenReturn(0L);
        when(empresaRepository.save(any(Empresa.class))).thenAnswer(i -> {
            Empresa e = i.getArgument(0);
            e.setId(1L);
            return e;
        });

        boolean creada = servicio.crearSiNoHay(
                "76.412.330-9", "Constructora Arauco Ltda.", "admin@arauco-ltda.cl", "clave-inicial-segura");

        assertThat(creada).isTrue();
        ArgumentCaptor<Usuario> admin = ArgumentCaptor.forClass(Usuario.class);
        verify(usuarioRepository).save(admin.capture());
        assertThat(admin.getValue().getRol()).isEqualTo(RolUsuario.ADMIN);
        assertThat(admin.getValue().getEmail()).isEqualTo("admin@arauco-ltda.cl");
        assertThat(admin.getValue().getEmpresa().getRut()).isEqualTo("76.412.330-9");
        assertThat(admin.getValue().autenticar("clave-inicial-segura")).isTrue();
        assertThat(admin.getValue().isDebeCambiarPin()).isTrue();
    }

    @Test
    void siYaHayEmpresasNoHaceNada() {
        when(empresaRepository.count()).thenReturn(3L);

        assertThat(servicio.crearSiNoHay("76.412.330-9", "X", "admin@x.cl", "clave-inicial-segura")).isFalse();

        verify(empresaRepository, never()).save(any());
        verify(usuarioRepository, never()).save(any());
    }

    @Test
    void sinClaveNoCreaNada() {
        assertThat(servicio.crearSiNoHay("76.412.330-9", "X", "admin@x.cl", "")).isFalse();
        assertThat(servicio.crearSiNoHay("76.412.330-9", "X", "admin@x.cl", null)).isFalse();

        verify(empresaRepository, never()).save(any());
    }

    @Test
    void unMarcadorDeEjemploNuncaEsLaClaveInicial() {
        assertThatThrownBy(() -> servicio.crearSiNoHay(
                "76.412.330-9", "X", "admin@x.cl", "CAMBIAR_generar_una_clave"))
                .isInstanceOf(IllegalStateException.class);

        verify(empresaRepository, never()).save(any());
    }

    @Test
    void unaClaveQueNoCumpleLaPoliticaNoDejaUnaEmpresaSinAdmin() {
        when(empresaRepository.count()).thenReturn(0L);

        assertThatThrownBy(() -> servicio.crearSiNoHay("76.412.330-9", "X", "admin@x.cl", "1234"))
                .isInstanceOf(IllegalArgumentException.class);

        // La clave se valida antes de guardar nada.
        verify(empresaRepository, never()).save(any());
    }
}
