package cl.duocuc.checkinobra.config;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.Instant;
import java.util.NoSuchElementException;
import java.util.stream.Collectors;

@RestControllerAdvice
public class ApiExceptionHandler {

    public record ErrorBody(Instant instante, int status, String mensaje) {
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

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorBody> validacion(MethodArgumentNotValidException ex) {
        String mensaje = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> e.getField() + ": " + e.getDefaultMessage())
                .collect(Collectors.joining("; "));
        return cuerpo(HttpStatus.BAD_REQUEST, mensaje);
    }

    private ResponseEntity<ErrorBody> cuerpo(HttpStatus status, String mensaje) {
        return ResponseEntity.status(status).body(new ErrorBody(Instant.now(), status.value(), mensaje));
    }
}
