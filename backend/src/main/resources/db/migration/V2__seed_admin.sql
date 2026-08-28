-- Semilla mínima para poder entrar por primera vez: sin ningún Usuario
-- creado, ningún endpoint protegido con @PreAuthorize("hasRole('ADMIN')")
-- se puede llamar (incluido el que crea usuarios). Este admin es el punto
-- de partida — la primera acción real debe ser cambiarle el PIN.
--
-- PIN de arranque: 0000 (hash BCrypt generado con
-- org.springframework.security.crypto.bcrypt.BCrypt, factor de costo 10).

INSERT INTO empresas (nombre, rut)
VALUES ('Constructora Arauco Ltda.', '76.412.330-9');

INSERT INTO usuarios (nombre, email, rol, pin_hash, empresa_id)
VALUES (
    'Administrador Check-In-Obra',
    'admin@arauco-ltda.cl',
    'ADMIN',
    '$2a$10$kFSIWta/.cMLeikoQc0JW.DMmNBA9nMPVHb/h7CDh3SwK3SxGMVui',
    (SELECT id FROM empresas WHERE rut = '76.412.330-9')
);
