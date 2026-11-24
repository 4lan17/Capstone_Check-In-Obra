package cl.duocuc.checkinobra.metricas;

import cl.duocuc.checkinobra.config.AccesoDenegadoException;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.SesionActual;
import cl.duocuc.checkinobra.inventario.EstadoHerramienta;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import cl.duocuc.checkinobra.presupuesto.DesgloseDeDesviacion;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Métricas de solo lectura para las pantallas de jefe, bodega y administrador (#203). Cada una se arma
 * con un puñado de consultas agregadas ({@link MetricasRepository}); acá solo se resuelve el periodo, se
 * comprueba el acceso a la obra y se da forma a la respuesta.
 *
 * <p>El periodo se cuenta en America/Santiago.
 */
@Service
@Transactional(readOnly = true)
public class MetricasService {

    static final ZoneId ZONA = ZoneId.of("America/Santiago");
    static final int MATERIALES_EN_EL_TOP_DEL_JEFE = 5;
    static final int MATERIALES_MAS_DESPACHADOS = 4;

    private final ObraService obraService;
    private final MetricasRepository repositorio;
    private final double umbralPct;

    public MetricasService(
            ObraService obraService,
            MetricasRepository repositorio,
            @Value("${checkinobra.presupuesto.umbral-desviacion-pct:10}") double umbralPct) {
        this.obraService = obraService;
        this.repositorio = repositorio;
        this.umbralPct = umbralPct;
    }

    // ---- jefe de terreno -------------------------------------------------

    public MetricasJefeResponse jefe(Long obraId, String parametroPeriodo) {
        Obra obra = obraService.obtener(obraId);
        exigirQueSeaJefeDeLaObraOAdmin(obra);
        PeriodoMetricas periodo = periodoDeLaObra(parametroPeriodo, obraId);
        LocalDateTime hastaExclusivo = periodo.hasta().plusDays(1).atStartOfDay();

        List<MetricasRepository.EjecutadoDeMaterial> materiales =
                repositorio.ejecutadoPorMaterial(obraId, hastaExclusivo).stream()
                        .sorted(Comparator.comparingDouble(MetricasRepository.EjecutadoDeMaterial::ejecutado).reversed()
                                .thenComparing(MetricasRepository.EjecutadoDeMaterial::nombre))
                        .toList();
        double ejecutadoTotal = materiales.stream().mapToDouble(MetricasRepository.EjecutadoDeMaterial::ejecutado).sum();

        List<MetricasJefeResponse.MaterialEjecutado> top = materiales.stream()
                .limit(MATERIALES_EN_EL_TOP_DEL_JEFE).map(this::filaDeMaterial).toList();
        List<MetricasRepository.EjecutadoDeMaterial> resto = materiales.stream().skip(MATERIALES_EN_EL_TOP_DEL_JEFE).toList();
        MetricasJefeResponse.Otros otros = new MetricasJefeResponse.Otros(resto.size(),
                DesgloseDeDesviacion.redondear(resto.stream().mapToDouble(MetricasRepository.EjecutadoDeMaterial::ejecutado).sum()));

        return new MetricasJefeResponse(
                periodo.codigo(), periodo.desde(), periodo.hasta(),
                new MetricasJefeResponse.GastoAcumulado(
                        DesgloseDeDesviacion.redondear(repositorio.presupuestoTotal(obraId)),
                        DesgloseDeDesviacion.redondear(ejecutadoTotal),
                        serieAcumulada(periodo, repositorio.gastoPorSemana(obraId, hastaExclusivo))),
                top, otros, umbralPct);
    }

    private MetricasJefeResponse.MaterialEjecutado filaDeMaterial(MetricasRepository.EjecutadoDeMaterial m) {
        Double pct = DesgloseDeDesviacion.porcentajeDeDesvio(m.presupuestado(), m.ejecutado());
        return new MetricasJefeResponse.MaterialEjecutado(
                m.materialId(), m.sku(), m.nombre(),
                DesgloseDeDesviacion.redondear(m.presupuestado()), DesgloseDeDesviacion.redondear(m.ejecutado()),
                pct, pct != null && pct > umbralPct);
    }

    /** Para cada semana del periodo, lo ejecutado desde el inicio de la obra hasta su cierre (o hasta hoy). */
    private static List<MetricasJefeResponse.PuntoSemanal> serieAcumulada(
            PeriodoMetricas periodo, List<MetricasRepository.GastoDeLaSemana> gastoPorSemana) {
        List<MetricasJefeResponse.PuntoSemanal> serie = new java.util.ArrayList<>();
        double acumulado = 0;
        int siguiente = 0;
        for (PeriodoMetricas.Semana semana : periodo.semanas()) {
            while (siguiente < gastoPorSemana.size() && !gastoPorSemana.get(siguiente).semana().isAfter(semana.desde())) {
                acumulado += gastoPorSemana.get(siguiente++).monto();
            }
            serie.add(new MetricasJefeResponse.PuntoSemanal(
                    semana.etiqueta(), semana.desde(), DesgloseDeDesviacion.redondear(acumulado)));
        }
        return serie;
    }

    private void exigirQueSeaJefeDeLaObraOAdmin(Obra obra) {
        if (SesionActual.usuario().rol() != RolUsuario.JEFE_TERRENO) {
            return;
        }
        boolean esSuObra = obra.getJefeTerreno() != null
                && obra.getJefeTerreno().getId().equals(SesionActual.usuarioId());
        if (!esSuObra) {
            throw new AccesoDenegadoException("Solo el jefe de terreno de la obra puede ver sus métricas");
        }
    }

    // ---- bodega ----------------------------------------------------------

    public MetricasBodegaResponse bodega(Long obraId, String parametroPeriodo) {
        Obra obra = obraService.obtener(obraId);
        PeriodoMetricas periodo = periodoDeLaObra(parametroPeriodo, obraId);

        Map<String, Long> herramientas = new LinkedHashMap<>();
        for (EstadoHerramienta e : EstadoHerramienta.values()) {
            herramientas.put(e.name(), 0L);
        }
        herramientas.putAll(repositorio.herramientasPorEstado(obra.getEmpresa().getId()));

        return new MetricasBodegaResponse(
                periodo.codigo(), periodo.desde(), periodo.hasta(),
                periodo.porSemana() ? "SEMANA" : "DIA",
                repositorio.movimientos(obraId, periodo),
                repositorio.masDespachados(obraId, periodo, MATERIALES_MAS_DESPACHADOS),
                herramientas,
                herramientas.values().stream().mapToLong(Long::longValue).sum(),
                repositorio.prestamosAbiertos(obraId));
    }

    // ---- empresa ---------------------------------------------------------

    public MetricasEmpresaResponse empresa(String parametroPeriodo) {
        Long empresaId = SesionActual.empresaId();
        LocalDate hoy = hoy();
        PeriodoMetricas periodo = PeriodoMetricas.resolver(
                parametroPeriodo, hoy, repositorio.primeraAlerta(empresaId).orElse(null));

        List<PeriodoMetricas.Semana> semanas = periodo.semanas();
        Map<LocalDate, MetricasRepository.AlertasDeLaSemana> conAlertas = repositorio
                .alertasPorSemana(empresaId, semanas.get(0).desde().atStartOfDay(), periodo.hasta().plusDays(1).atStartOfDay())
                .stream().collect(Collectors.toMap(MetricasRepository.AlertasDeLaSemana::semana, Function.identity()));
        List<MetricasEmpresaResponse.AlertasDeLaSemana> alertas = semanas.stream().map(s -> {
            MetricasRepository.AlertasDeLaSemana a = conAlertas.get(s.desde());
            return new MetricasEmpresaResponse.AlertasDeLaSemana(
                    s.etiqueta(), s.desde(), a == null ? 0 : a.generadas(), a == null ? 0 : a.resueltas());
        }).toList();

        List<MetricasEmpresaResponse.DesviacionDeObra> desviaciones = repositorio
                .presupuestoYEjecutadoDeObrasActivas(empresaId).stream()
                .map(o -> new MetricasEmpresaResponse.DesviacionDeObra(
                        o.obraId(), o.nombre(), DesgloseDeDesviacion.porcentajeDeDesvio(o.presupuestado(), o.ejecutado())))
                .toList();

        return new MetricasEmpresaResponse(
                periodo.codigo(), periodo.desde(), periodo.hasta(), alertas, desviaciones, umbralPct,
                conCeros(RolDeEmpresa.nombres(), repositorio.usuariosPorRol(empresaId)),
                conCeros(java.util.Arrays.stream(EstadoObra.values()).map(Enum::name).toList(),
                        repositorio.obrasPorEstado(empresaId)));
    }

    // ---- común -----------------------------------------------------------

    private PeriodoMetricas periodoDeLaObra(String parametro, Long obraId) {
        // El primer movimiento solo importa para "obra"; para 7d y 30d no se consulta.
        boolean desdeElInicio = parametro != null && parametro.trim().equalsIgnoreCase("obra");
        LocalDate inicio = desdeElInicio ? repositorio.primerMovimiento(obraId).orElse(null) : null;
        return PeriodoMetricas.resolver(parametro, hoy(), inicio);
    }

    private static LocalDate hoy() {
        return LocalDate.now(ZONA);
    }

    /** Todas las claves, aunque no haya ninguna fila: el cliente no tiene que adivinar cuáles faltan. */
    private static Map<String, Long> conCeros(List<String> claves, Map<String, Long> conteo) {
        Map<String, Long> completo = new LinkedHashMap<>();
        claves.forEach(c -> completo.put(c, conteo.getOrDefault(c, 0L)));
        return completo;
    }

    /** Los roles que pertenecen a una empresa: PLATAFORMA vive en el catálogo, no en {@code usuarios}. */
    private static final class RolDeEmpresa {
        static List<String> nombres() {
            return java.util.Arrays.stream(RolUsuario.values())
                    .filter(r -> r != RolUsuario.PLATAFORMA).map(Enum::name).toList();
        }
    }
}
