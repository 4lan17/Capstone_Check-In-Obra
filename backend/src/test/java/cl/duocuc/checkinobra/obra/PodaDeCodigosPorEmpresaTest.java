package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.ResolutorDeBases;
import cl.duocuc.checkinobra.config.TenantContext;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import javax.sql.DataSource;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * SEG13 (#101): {@code podarVencidos} corre fuera de una petición, sin empresa en el contexto, igual
 * que la purga de claves de idempotencia (MT2). Recorre las empresas fijando la de cada una, y si una
 * falla sigue con las demás.
 */
class PodaDeCodigosPorEmpresaTest {

    private final ResolutorDeBases resolutor = new ResolutorDeBases() {
        @Override
        public DataSource baseDe(Long empresaId) {
            throw new UnsupportedOperationException();
        }

        @Override
        public boolean conoce(Long empresaId) {
            return true;
        }

        @Override
        public Collection<Long> empresas() {
            return List.of(3L, 4L, 5L);
        }
    };

    private CodigoCredencialService servicio(JdbcTemplate jdbc) {
        return new CodigoCredencialService(mock(CodigoCredencialRepository.class), jdbc, resolutor, 120, 20, 30, 600, 600);
    }

    @Test
    void recorreCadaEmpresaConSuPropiaBaseEnElContexto() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        List<Optional<Long>> vistas = new ArrayList<>();
        when(jdbc.update(anyString(), any(Object[].class))).thenAnswer(i -> {
            vistas.add(TenantContext.actual());
            return 0;
        });

        servicio(jdbc).podarVencidos();

        assertThat(vistas).containsExactly(Optional.of(3L), Optional.of(4L), Optional.of(5L));
        assertThat(TenantContext.actual()).isEmpty();
    }

    @Test
    void siUnaBaseFallaSigueConLasDemas() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        List<Long> podadas = new ArrayList<>();
        when(jdbc.update(anyString(), any(Object[].class))).thenAnswer(i -> {
            Long empresa = TenantContext.actual().orElseThrow();
            if (empresa == 4L) {
                throw new IllegalStateException("la base de la empresa 4 no responde");
            }
            podadas.add(empresa);
            return 0;
        });

        servicio(jdbc).podarVencidos();

        assertThat(podadas).containsExactly(3L, 5L);
    }
}
