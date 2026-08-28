package cl.duocuc.checkinobra.config;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;

/**
 * Emite y valida los JWT que resultan de Usuario.autenticar()/
 * autenticarPorEmail(). El token lleva el id de usuario, su rol y su
 * empresa — lo mínimo que necesita el resto de la API para autorizar.
 */
@Component
public class JwtService {

    private final SecretKey key;
    private final long expiracionMinutos;

    public JwtService(
            @Value("${checkinobra.jwt.secret}") String secret,
            @Value("${checkinobra.jwt.expiracion-minutos:480}") long expiracionMinutos) {
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.expiracionMinutos = expiracionMinutos;
    }

    public String emitir(Usuario usuario) {
        Date ahora = new Date();
        Date expira = new Date(ahora.getTime() + expiracionMinutos * 60_000);
        return Jwts.builder()
                .subject(usuario.getId().toString())
                .claim("email", usuario.getEmail())
                .claim("rol", usuario.getRol().name())
                .claim("empresaId", usuario.getEmpresa().getId())
                .issuedAt(ahora)
                .expiration(expira)
                .signWith(key)
                .compact();
    }

    public Claims validarYExtraer(String token) {
        return Jwts.parser()
                .verifyWith(key)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }
}
