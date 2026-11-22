package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.AlmacenDeSecretos;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas.EmpresaRegistrada;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.MigradorDeBases;
import cl.duocuc.checkinobra.config.ResolutorDeBases;
import cl.duocuc.checkinobra.config.Rut;
import cl.duocuc.checkinobra.plataforma.BarridoDeAltas.AltaIncompleta;
import cl.duocuc.checkinobra.plataforma.BarridoDeAltas.Tipo;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.test.util.ReflectionTestUtils;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Mejora #154 (origen: límite anotado en #110 y PR #147): si el proceso se corta a mitad del alta de
 * una constructora, queda una empresa a medias (registro, base, usuario de PostgreSQL o secreto) y
 * nada la detectaba. Estas pruebas simulan el corte armando a mano los pasos que {@code AltaDeEmpresaService}
 * hace en orden, sin las compensaciones, contra Postgres real y con el enrutador de verdad.
 *
 * <p>Los tres cortes: solo el catálogo, la base creada pero sin migrar, y la base sembrada sin su ADMIN.
 *
 * <p>Comparte contexto de Spring con {@code SuspensionDeEmpresaTest} y {@code RespaldoPorBaseTest} (mismas
 * propiedades, sin sobrescribir beans): cada contexto nuevo abre sus propios pools, y la suite ya está cerca
 * de las 100 conexiones de un PostgreSQL por defecto. Por eso la gracia (10 minutos) se baja a 0 con
 * reflexión solo mientras corre cada prueba.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "checkinobra.pruebas.conexion-compartida=false",
                "spring.jpa.hibernate.ddl-auto=none",
                "spring.jpa.properties.hibernate.boot.allow_jdbc_metadata_access=false"})
class BarridoDeAltasTest {

    private enum Corte { SOLO_CATALOGO, BASE_SIN_MIGRAR, SEMBRADA_SIN_ADMIN }

    private static final String CLAVE_OPERADOR = "clave-del-operador-9";

    @LocalServerPort private int puerto;
    @Autowired private BarridoDeAltas barrido;
    @Autowired private CatalogoDeEmpresas catalogo;
    @Autowired private AprovisionadorDeBases aprovisionador;
    @Autowired private AlmacenDeSecretos secretos;
    @Autowired private MigradorDeBases migrador;
    @Autowired private ResolutorDeBases resolutor;
    @Autowired private JwtService jwtService;

    @Value("${checkinobra.catalogo.url}") private String urlCatalogo;
    @Value("${checkinobra.catalogo.username}") private String usuarioCatalogo;
    @Value("${checkinobra.catalogo.password}") private String claveCatalogo;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();
    /** Dígitos de RUT de todo lo que la prueba crea, para limpiarlo aunque falle. */
    private final List<String> digitosCreados = new ArrayList<>();
    private final List<Long> operadores = new ArrayList<>();
    private JdbcTemplate enElCatalogo;

    @BeforeEach
    void preparar() {
        enElCatalogo = new JdbcTemplate(new DriverManagerDataSource(urlCatalogo, usuarioCatalogo, claveCatalogo));
        // Lo que se arma acá se registra "ahora": sin esto el barrido lo tomaría por un alta en curso.
        ReflectionTestUtils.setField(barrido, "gracia", Duration.ZERO);
    }

    @AfterEach
    void limpiar() {
        ReflectionTestUtils.setField(barrido, "gracia", Duration.ofMinutes(10));
        for (String digitos : digitosCreados) {
            catalogo.listar().stream().filter(e -> e.nombreBase().equals("checkinobra_e" + digitos))
                    .forEach(e -> catalogo.eliminarEmpresa(e.id()));
        }
        resolutor.refrescar();
        for (String digitos : digitosCreados) {
            aprovisionador.eliminar("checkinobra_e" + digitos, "app_e" + digitos);
            secretos.borrar("app_e" + digitos);
        }
        operadores.forEach(id -> enElCatalogo.update("DELETE FROM operadores WHERE id = ?", id));
        resolutor.refrescar();
    }

    // ---- detectar -----------------------------------------------------------------------------

    @Test
    void unCorteSoloEnElCatalogoSeListaConLoQueLeFalta() {
        EmpresaRegistrada e = cortarEn(Corte.SOLO_CATALOGO);

        AltaIncompleta alta = propia(e.nombreBase(), Tipo.EMPRESA_A_MEDIAS).orElseThrow();

        assertThat(alta.empresaId()).isEqualTo(e.id());
        assertThat(alta.problemas()).contains(
                BarridoDeAltas.SIN_BASE, BarridoDeAltas.SIN_USUARIO_DE_BASE, BarridoDeAltas.SIN_SECRETO,
                BarridoDeAltas.SIN_MIGRAR);
        assertThat(alta.sePuedeReanudar()).isTrue();
        assertThat(alta.sePuedeDeshacer()).isTrue();
    }

    @Test
    void unCorteConLaBaseCreadaPeroSinMigrarSeListaComoSinMigrar() {
        EmpresaRegistrada e = cortarEn(Corte.BASE_SIN_MIGRAR);

        AltaIncompleta alta = propia(e.nombreBase(), Tipo.EMPRESA_A_MEDIAS).orElseThrow();

        assertThat(alta.problemas()).contains(BarridoDeAltas.SIN_MIGRAR)
                .doesNotContain(BarridoDeAltas.SIN_BASE, BarridoDeAltas.SIN_USUARIO_DE_BASE, BarridoDeAltas.SIN_SECRETO);
    }

    @Test
    void unCorteConLaBaseSembradaPeroSinAdminSeListaComoSinAdministrador() {
        EmpresaRegistrada e = cortarEn(Corte.SEMBRADA_SIN_ADMIN);

        AltaIncompleta alta = propia(e.nombreBase(), Tipo.EMPRESA_A_MEDIAS).orElseThrow();

        assertThat(alta.problemas()).containsExactly(BarridoDeAltas.SIN_ADMINISTRADOR);
    }

    @Test
    void unaEmpresaCompletaNoSeListaNiSePuedeDeshacer() {
        EmpresaRegistrada e = cortarEn(Corte.SEMBRADA_SIN_ADMIN);
        barrido.reanudar(e.id());

        assertThat(propia(e.nombreBase(), Tipo.EMPRESA_A_MEDIAS)).isEmpty();
        assertThatThrownBy(() -> barrido.deshacer(Tipo.EMPRESA_A_MEDIAS, e.nombreBase(), e.nombreBase()))
                .isInstanceOf(IllegalStateException.class);
        assertThat(aprovisionador.existeBase(e.nombreBase())).isTrue();
        assertThat(catalogo.buscarPorBase(e.nombreBase())).isPresent();
    }

    @Test
    void unaBaseUnUsuarioYUnSecretoSinRegistroSeListanComoHuerfanos() {
        String digitos = digitosNuevos();
        String base = "checkinobra_e" + digitos;
        String usuario = "app_e" + digitos;
        secretos.guardar(usuario, "clave-huerfana-" + digitos);
        aprovisionador.crear(base, usuario, secretos.leer(usuario));
        String soloUsuario = "app_e" + digitosNuevos();
        // Un usuario sin base: el aprovisionador lo crea junto con la base, así que se borra la base.
        aprovisionador.crear("checkinobra_e" + soloUsuario.substring(5), soloUsuario, "clave-del-usuario-solo-1");
        aprovisionador.eliminarBase("checkinobra_e" + soloUsuario.substring(5));
        String soloSecreto = "app_e" + digitosNuevos();
        secretos.guardar(soloSecreto, "clave-del-secreto-solo-1");

        List<AltaIncompleta> altas = barrido.detectar();

        assertThat(altas).anySatisfy(a -> {
            assertThat(a.tipo()).isEqualTo(Tipo.BASE_SIN_REGISTRO);
            assertThat(a.referencia()).isEqualTo(base);
        });
        assertThat(altas).anySatisfy(a -> {
            assertThat(a.tipo()).isEqualTo(Tipo.USUARIO_SIN_REGISTRO);
            assertThat(a.referencia()).isEqualTo(soloUsuario);
        });
        assertThat(altas).anySatisfy(a -> {
            assertThat(a.tipo()).isEqualTo(Tipo.SECRETO_HUERFANO);
            assertThat(a.referencia()).isEqualTo(soloSecreto);
        });
    }

    @Test
    void lasBasesYSecretosDeEmpresasRegistradasYLasBasesDeInfraestructuraNoSonHuerfanos() {
        EmpresaRegistrada e = cortarEn(Corte.BASE_SIN_MIGRAR);

        List<AltaIncompleta> altas = barrido.detectar();

        assertThat(altas).noneMatch(a -> a.tipo() != Tipo.EMPRESA_A_MEDIAS && a.referencia().equals(e.nombreBase()));
        assertThat(altas).noneMatch(a -> a.tipo() == Tipo.SECRETO_HUERFANO && a.referencia().equals(e.usuarioBase()));
        assertThat(altas).noneMatch(a -> a.tipo() == Tipo.BASE_SIN_REGISTRO
                && List.of("checkinobra", "checkinobra_b", "checkinobra_catalogo").contains(a.referencia()));
    }

    @Test
    void unaEmpresaRecienRegistradaSeDejaPasarPorqueQuizasEsUnAltaEnCurso() {
        ReflectionTestUtils.setField(barrido, "gracia", Duration.ofMinutes(10));
        EmpresaRegistrada e = cortarEn(Corte.SOLO_CATALOGO);

        assertThat(propia(e.nombreBase(), Tipo.EMPRESA_A_MEDIAS)).isEmpty();
        assertThatThrownBy(() -> barrido.deshacer(Tipo.EMPRESA_A_MEDIAS, e.nombreBase(), e.nombreBase()))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("en curso");
        assertThatThrownBy(() -> barrido.reanudar(e.id()))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("en curso");
        assertThat(catalogo.buscarPorBase(e.nombreBase())).isPresent();
    }

    // ---- deshacer -----------------------------------------------------------------------------

    @Test
    void deshacerUnaEmpresaCortadaBorraTodoYElRutSePuedeDarDeAltaOtraVez() throws Exception {
        EmpresaRegistrada e = cortarEn(Corte.BASE_SIN_MIGRAR);

        barrido.deshacer(Tipo.EMPRESA_A_MEDIAS, e.nombreBase(), e.nombreBase());

        assertThat(catalogo.buscarPorBase(e.nombreBase())).isEmpty();
        assertThat(catalogo.empresaDeCorreo(correoDe(e))).isEmpty();
        assertThat(aprovisionador.existeBase(e.nombreBase())).isFalse();
        assertThat(aprovisionador.existeUsuario(e.usuarioBase())).isFalse();
        assertThat(secretos.existe(e.usuarioBase())).isFalse();
        // Y el operador puede repetir el alta con el mismo RUT.
        String token = tokenDeOperador();
        HttpResponse<String> alta = enviar("POST", "/api/plataforma/empresas", token,
                "{\"rut\":\"" + e.rut() + "\",\"nombre\":\"Constructora cortada\",\"adminEmail\":\"otro-"
                        + UUID.randomUUID().toString().substring(0, 8) + "@constructora.cl\"}");
        assertThat(alta.statusCode()).as(alta.body()).isEqualTo(201);
    }

    @Test
    void deshacerExigeEscribirElIdentificadorYSinEsoNoBorraNada() {
        EmpresaRegistrada e = cortarEn(Corte.BASE_SIN_MIGRAR);

        assertThatThrownBy(() -> barrido.deshacer(Tipo.EMPRESA_A_MEDIAS, e.nombreBase(), "si"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> barrido.deshacer(Tipo.EMPRESA_A_MEDIAS, e.nombreBase(), null))
                .isInstanceOf(IllegalArgumentException.class);

        assertThat(catalogo.buscarPorBase(e.nombreBase())).isPresent();
        assertThat(aprovisionador.existeBase(e.nombreBase())).isTrue();
    }

    @Test
    void deshacerNoTocaUnaBaseQueNoSigueLaConvencionDelAlta() {
        // La base de esta suite no se creó con el alta: ni se lista ni se puede borrar con esto.
        String nombreBaseDeLaSuite = catalogo.nombreBaseActual();

        assertThatThrownBy(() -> barrido.deshacer(Tipo.BASE_SIN_REGISTRO, nombreBaseDeLaSuite, nombreBaseDeLaSuite))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> barrido.deshacer(Tipo.EMPRESA_A_MEDIAS, nombreBaseDeLaSuite, nombreBaseDeLaSuite))
                .isInstanceOf(RuntimeException.class);
        assertThat(aprovisionador.existeBase(nombreBaseDeLaSuite)).isTrue();
    }

    @Test
    void deshacerUnaBaseUnUsuarioYUnSecretoHuerfanosLosBorra() {
        String digitos = digitosNuevos();
        String base = "checkinobra_e" + digitos;
        String usuario = "app_e" + digitos;
        secretos.guardar(usuario, "clave-huerfana-" + digitos);
        aprovisionador.crear(base, usuario, secretos.leer(usuario));

        barrido.deshacer(Tipo.BASE_SIN_REGISTRO, base, base);
        assertThat(aprovisionador.existeBase(base)).isFalse();
        barrido.deshacer(Tipo.USUARIO_SIN_REGISTRO, usuario, usuario);
        assertThat(aprovisionador.existeUsuario(usuario)).isFalse();
        barrido.deshacer(Tipo.SECRETO_HUERFANO, usuario, usuario);
        assertThat(secretos.existe(usuario)).isFalse();
    }

    @Test
    void unaBaseSinRegistroQueYaTieneUnRegistroNoSeBorra() {
        EmpresaRegistrada e = cortarEn(Corte.BASE_SIN_MIGRAR);

        // El identificador es el de una base que sí está en el catálogo: no es huérfana.
        assertThatThrownBy(() -> barrido.deshacer(Tipo.BASE_SIN_REGISTRO, e.nombreBase(), e.nombreBase()))
                .isInstanceOf(IllegalStateException.class);
        assertThat(aprovisionador.existeBase(e.nombreBase())).isTrue();
    }

    @Test
    void unaEmpresaEnUsoQuePerdioSuSecretoSeListaPeroNoSeBorraYSeRepara() {
        EmpresaRegistrada e = cortarEn(Corte.SEMBRADA_SIN_ADMIN);
        barrido.reanudar(e.id());
        // En uso: tiene su ADMIN. El volumen de secretos se pierde.
        secretos.borrar(e.usuarioBase());

        AltaIncompleta alta = propia(e.nombreBase(), Tipo.EMPRESA_A_MEDIAS).orElseThrow();
        assertThat(alta.problemas()).contains(BarridoDeAltas.SIN_SECRETO).doesNotContain(BarridoDeAltas.SIN_ADMINISTRADOR);
        assertThat(alta.sePuedeDeshacer()).isFalse();
        assertThatThrownBy(() -> barrido.deshacer(Tipo.EMPRESA_A_MEDIAS, e.nombreBase(), e.nombreBase()))
                .isInstanceOf(IllegalStateException.class);
        assertThat(aprovisionador.existeBase(e.nombreBase())).isTrue();
        assertThat(catalogo.buscarPorBase(e.nombreBase())).isPresent();

        // Reanudar la repara sin crear otro administrador.
        AltaDeEmpresaService.Resultado r = barrido.reanudar(e.id());
        assertThat(r.claveTemporal()).isNull();
        assertThat(secretos.existe(e.usuarioBase())).isTrue();
        assertThat(propia(e.nombreBase(), Tipo.EMPRESA_A_MEDIAS)).isEmpty();
    }

    @Test
    void unaBaseSinRegistroConAdministradorNoSeBorra() {
        EmpresaRegistrada e = cortarEn(Corte.SEMBRADA_SIN_ADMIN);
        barrido.reanudar(e.id());
        // Se pierde el registro del catálogo, pero la base sigue siendo la de una empresa en uso.
        catalogo.eliminarEmpresa(e.id());
        resolutor.refrescar();

        AltaIncompleta alta = propia(e.nombreBase(), Tipo.BASE_SIN_REGISTRO).orElseThrow();
        assertThat(alta.sePuedeDeshacer()).isFalse();
        assertThatThrownBy(() -> barrido.deshacer(Tipo.BASE_SIN_REGISTRO, e.nombreBase(), e.nombreBase()))
                .isInstanceOf(IllegalStateException.class);
        assertThat(aprovisionador.existeBase(e.nombreBase())).isTrue();
    }

    // ---- reanudar -----------------------------------------------------------------------------

    @Test
    void reanudarDesdeCualquierCorteDejaLaEmpresaFuncionandoYSuAdminEntra() throws Exception {
        for (Corte corte : Corte.values()) {
            EmpresaRegistrada e = cortarEn(corte);

            AltaDeEmpresaService.Resultado r = barrido.reanudar(e.id());

            assertThat(r.empresaId()).isEqualTo(e.id());
            assertThat(r.claveTemporal()).as("clave temporal de " + corte).isNotBlank();
            assertThat(resolutor.conoce(e.id())).as("pool de " + corte).isTrue();
            assertThat(propia(e.nombreBase(), Tipo.EMPRESA_A_MEDIAS)).as("lista de " + corte).isEmpty();
            JsonNode login = json.readTree(enviar("POST", "/api/auth/login", null,
                    "{\"email\":\"" + correoDe(e) + "\",\"pin\":\"" + r.claveTemporal() + "\"}").body());
            assertThat(login.get("debeCambiarClave").asBoolean()).as("login de " + corte).isTrue();
        }
    }

    @Test
    void reanudarConElSecretoPerdidoLoRegeneraYLaBaseSigueAbriendose() {
        EmpresaRegistrada e = cortarEn(Corte.SEMBRADA_SIN_ADMIN);
        secretos.borrar(e.usuarioBase());

        barrido.reanudar(e.id());

        assertThat(secretos.existe(e.usuarioBase())).isTrue();
        assertThat(resolutor.conoce(e.id())).isTrue();
    }

    @Test
    void sinCorreoReservadoNoSePuedeReanudarPeroSiDeshacer() {
        EmpresaRegistrada e = cortarEn(Corte.SOLO_CATALOGO);
        catalogo.liberarCorreo(correoDe(e), e.id());

        AltaIncompleta alta = propia(e.nombreBase(), Tipo.EMPRESA_A_MEDIAS).orElseThrow();
        assertThat(alta.sePuedeReanudar()).isFalse();
        assertThat(alta.sePuedeDeshacer()).isTrue();
        assertThatThrownBy(() -> barrido.reanudar(e.id())).isInstanceOf(IllegalStateException.class);

        barrido.deshacer(Tipo.EMPRESA_A_MEDIAS, e.nombreBase(), e.nombreBase());
        assertThat(catalogo.buscarPorBase(e.nombreBase())).isEmpty();
    }

    // ---- por HTTP -----------------------------------------------------------------------------

    @Test
    void elOperadorListaYDeshaceDesdeLaApiYSoloElOperador() throws Exception {
        EmpresaRegistrada e = cortarEn(Corte.BASE_SIN_MIGRAR);
        String token = tokenDeOperador();

        assertThat(enviar("GET", "/api/plataforma/altas-incompletas", null, null).statusCode()).isIn(401, 403);
        HttpResponse<String> lista = enviar("GET", "/api/plataforma/altas-incompletas", token, null);
        assertThat(lista.statusCode()).isEqualTo(200);
        assertThat(lista.body()).contains(e.nombreBase());
        // Lo que sirve para abrir la base no sale en la lista.
        assertThat(lista.body()).doesNotContain(e.usuarioBase() + "\"").doesNotContain("secreto");

        String cuerpoSinConfirmar = "{\"tipo\":\"EMPRESA_A_MEDIAS\",\"referencia\":\"" + e.nombreBase() + "\",\"confirmar\":\"no\"}";
        assertThat(enviar("POST", "/api/plataforma/altas-incompletas/deshacer", token, cuerpoSinConfirmar).statusCode())
                .isEqualTo(400);
        assertThat(aprovisionador.existeBase(e.nombreBase())).isTrue();

        String cuerpo = "{\"tipo\":\"EMPRESA_A_MEDIAS\",\"referencia\":\"" + e.nombreBase() + "\",\"confirmar\":\"" + e.nombreBase() + "\"}";
        HttpResponse<String> deshecha = enviar("POST", "/api/plataforma/altas-incompletas/deshacer", token, cuerpo);
        assertThat(deshecha.statusCode()).as(deshecha.body()).isEqualTo(204);
        assertThat(aprovisionador.existeBase(e.nombreBase())).isFalse();
    }

    @Test
    void elOperadorReanudaDesdeLaApiYRecibeLaClaveTemporalDelAdmin() throws Exception {
        EmpresaRegistrada e = cortarEn(Corte.SEMBRADA_SIN_ADMIN);
        String token = tokenDeOperador();

        assertThat(enviar("POST", "/api/plataforma/altas-incompletas/" + e.id() + "/reanudar", null, null).statusCode())
                .isIn(401, 403);
        HttpResponse<String> r = enviar("POST", "/api/plataforma/altas-incompletas/" + e.id() + "/reanudar", token, null);

        assertThat(r.statusCode()).as(r.body()).isEqualTo(200);
        JsonNode cuerpo = json.readTree(r.body());
        assertThat(cuerpo.get("id").asLong()).isEqualTo(e.id());
        assertThat(cuerpo.get("claveTemporal").asString()).isNotBlank();
        // Ya completa: reanudar otra vez es un 409, no crea otro administrador.
        assertThat(enviar("POST", "/api/plataforma/altas-incompletas/" + e.id() + "/reanudar", token, null).statusCode())
                .isEqualTo(409);
    }

    // ---- ayudas -------------------------------------------------------------------------------

    private Optional<AltaIncompleta> propia(String referencia, Tipo tipo) {
        return barrido.detectar().stream()
                .filter(a -> a.tipo() == tipo && a.referencia().equals(referencia)).findFirst();
    }

    private String correoDe(EmpresaRegistrada e) {
        return "admin-" + e.nombreBase() + "@constructora.cl";
    }

    /** Arma a mano los pasos del alta, en su orden y sin compensaciones, hasta el corte. */
    private EmpresaRegistrada cortarEn(Corte corte) {
        String rut = Rut.normalizar(rutNuevo());
        String digitos = rut.replaceAll("[^0-9K]", "").toLowerCase();
        digitosCreados.add(digitos);
        String base = "checkinobra_e" + digitos;
        String usuario = "app_e" + digitos;
        long id = catalogo.registrar(null, rut, "Constructora cortada", base, usuario, AlmacenDeSecretos.PREFIJO + usuario);
        EmpresaRegistrada registrada = catalogo.buscarPorBase(base).orElseThrow();
        assertThat(catalogo.reservarCorreo(correoDe(registrada), id)).isTrue();
        if (corte == Corte.SOLO_CATALOGO) {
            return registrada;
        }
        secretos.guardar(usuario, "clave-de-la-base-" + digitos);
        aprovisionador.crear(base, usuario, secretos.leer(usuario));
        if (corte == Corte.BASE_SIN_MIGRAR) {
            return registrada;
        }
        assertThat(migrador.migrar(registrada).ok()).isTrue();
        aprovisionador.sembrar(base, id, "Constructora cortada", rut, false);
        return catalogo.buscarPorBase(base).orElseThrow();
    }

    private String digitosNuevos() {
        String d = String.valueOf(ThreadLocalRandom.current().nextLong(100_000_000L, 999_999_999L));
        digitosCreados.add(d);
        return d;
    }

    private String rutNuevo() {
        String cuerpo = String.valueOf(10_000_000 + ThreadLocalRandom.current().nextInt(80_000_000));
        int suma = 0;
        int factor = 2;
        for (int i = cuerpo.length() - 1; i >= 0; i--) {
            suma += (cuerpo.charAt(i) - '0') * factor;
            factor = factor == 7 ? 2 : factor + 1;
        }
        int resto = 11 - suma % 11;
        char dv = resto == 11 ? '0' : resto == 10 ? 'K' : (char) ('0' + resto);
        return cuerpo.substring(0, 2) + "." + cuerpo.substring(2, 5) + "." + cuerpo.substring(5) + "-" + dv;
    }

    private String tokenDeOperador() throws Exception {
        String correo = "operador-" + UUID.randomUUID().toString().substring(0, 8) + "@plataforma.cl";
        operadores.add(catalogo.crearOperador(correo, "Operadora", BCrypt.hashpw(CLAVE_OPERADOR, BCrypt.gensalt()))
                .orElseThrow());
        return json.readTree(enviar("POST", "/api/plataforma/auth/login", null,
                "{\"email\":\"" + correo + "\",\"clave\":\"" + CLAVE_OPERADOR + "\"}").body()).get("token").asString();
    }

    private HttpResponse<String> enviar(String metodo, String ruta, String jwt, String cuerpo) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Content-Type", "application/json");
        if (jwt != null) {
            b.header("Authorization", "Bearer " + jwt);
        }
        b.method(metodo, cuerpo == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(cuerpo));
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }
}
