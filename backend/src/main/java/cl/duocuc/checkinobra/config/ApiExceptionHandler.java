package cl.duocuc.checkinobra.config;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import com.fasterxml.jackson.databind.exc.InvalidFormatException;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.stream.Collectors;

@RestControllerAdvice
public class ApiExceptionHandler {

    public record ErrorBody(Instant instante, int status, String mensaje) {
    }

    @ExceptionHandler(AccesoDenegadoException.class)
    public ResponseEntity<ErrorBody> accesoDenegado(AccesoDenegadoException ex) {
        return cuerpo(HttpStatus.FORBIDDEN, ex.getMessage());
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<ErrorBody> noEncontrado(NoSuchElementException ex) {
        return cuerpo(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<ErrorBody> conflicto(IllegalStateException ex) {
        return cuerpo(HttpStatus.CONFLICT, ex.getMessage());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorBody> solicitudInvalida(IllegalArgumentException ex) {
        return cuerpo(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    /**
     * Cuerpo ilegible: JSON roto, o un valor que no calza con el tipo esperado —
     * el caso típico es un enum inventado, como {@code "categoria": "PLANCHA"}.
     *
     * <p>Sin este manejador la excepción salía del controlador sin atender, Spring
     * la reenviaba a {@code /error}, y esa ruta no está permitida en
     * {@link SecurityConfig}: el resultado era un <b>403 con cuerpo vacío</b> ante
     * un simple error de tipeo en la petición. Depurar eso desde la app es
     * imposible: dice "no tienes permiso" cuando el permiso estaba bien.
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ErrorBody> cuerpoIlegible(HttpMessageNotReadableException ex) {
        return cuerpo(HttpStatus.BAD_REQUEST, causaLegible(ex));
    }

    /** Un query param con el tipo equivocado: {@code ?obraId=abc}. */
    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ErrorBody> tipoInvalido(MethodArgumentTypeMismatchException ex) {
        return cuerpo(HttpStatus.BAD_REQUEST, "El parámetro '" + ex.getName() + "' no tiene un valor válido");
    }

    /** Falta un query param obligatorio. */
    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<ErrorBody> faltaParametro(MissingServletRequestParameterException ex) {
        return cuerpo(HttpStatus.BAD_REQUEST, "Falta el parámetro obligatorio '" + ex.getParameterName() + "'");
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorBody> validacion(MethodArgumentNotValidException ex) {
        String mensaje = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> e.getField() + ": " + e.getDefaultMessage())
                .collect(Collectors.joining("; "));
        return cuerpo(HttpStatus.BAD_REQUEST, mensaje);
    }

    /**
     * Jackson explica bien el problema, pero en varias líneas y citando la clase
     * Java. Se rescata la primera línea, que es la que le sirve a quien llama, sin
     * filtrar los nombres internos del backend.
     */
    private String causaLegible(HttpMessageNotReadableException ex) {
        // Se recorre la cadena entera porque, al deserializar un `record`, la
        // causa más específica no siempre es la que explica el problema.
        //
        // Y se pregunta por las dos clases a propósito: en el classpath conviven
        // Jackson 2 (`com.fasterxml.jackson`, que usan JJWT y los tests) y
        // Jackson 3 (`tools.jackson`, que es el que Spring Boot 4 usa para
        // convertir las peticiones HTTP). Son `InvalidFormatException`
        // distintos y sin parentesco: mirar solo el de Jackson 2 hacía que este
        // método nunca reconociera un enum inválido llegado por HTTP.
        for (Throwable causa = ex; causa != null; causa = causa.getCause()) {
            if (causa instanceof InvalidFormatException j2) {
                return explicar(j2.getValue(), campoDe(j2.getPath()), j2.getTargetType());
            }
            if (causa instanceof tools.jackson.databind.exc.InvalidFormatException j3) {
                return explicar(j3.getValue(), campoDe(j3.getPath()), j3.getTargetType());
            }
        }
        return "El cuerpo de la petición no se pudo leer: revisa que sea JSON válido";
    }

    private String campoDe(List<? extends Object> ruta) {
        if (ruta.isEmpty()) {
            return "un campo";
        }
        Object ultima = ruta.getLast();
        if (ultima instanceof com.fasterxml.jackson.databind.JsonMappingException.Reference r) {
            return r.getFieldName() == null ? "un campo" : r.getFieldName();
        }
        // Jackson 3 renombró `getFieldName()` a `getPropertyName()`.
        if (ultima instanceof tools.jackson.core.JacksonException.Reference r) {
            return r.getPropertyName() == null ? "un campo" : r.getPropertyName();
        }
        return "un campo";
    }

    /** Para un enum, listar los valores válidos ahorra ir a leer el código. */
    private String explicar(Object valor, String campo, Class<?> tipoEsperado) {
        String valores = tipoEsperado != null && tipoEsperado.isEnum()
                ? " (valores válidos: "
                        + Arrays.stream(tipoEsperado.getEnumConstants())
                                .map(Object::toString)
                                .collect(Collectors.joining(", "))
                        + ")"
                : "";
        return "El valor '" + valor + "' no es válido para " + campo + valores;
    }

    private ResponseEntity<ErrorBody> cuerpo(HttpStatus status, String mensaje) {
        return ResponseEntity.status(status).body(new ErrorBody(Instant.now(), status.value(), mensaje));
    }
}
