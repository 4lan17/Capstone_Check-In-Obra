-- SEG13 (#101, S-27 y S-30): la credencial del trabajador deja de ser un QR fijo.
--
-- 1) S-30: IdempotenciaFilter guardaba, para repetírsela a un reintento, la respuesta de cada
--    escritura con Idempotency-Key. Las de credenciales (el alta, la renovación) llevaban el
--    credencialQr en claro, y quedaban en esta tabla. Desde esta versión esas rutas no se guardan
--    (IdempotenciaFilter); acá se borra lo que ya se había guardado.
--
--    `position(... in bytea)` y no un LIKE sobre el texto: el cuerpo puede ser binario (una planilla)
--    y convertirlo a texto fallaría con bytes que no son UTF-8.
DELETE FROM claves_idempotencia
 WHERE position(convert_to('credencialQr', 'UTF8') IN cuerpo) > 0
    OR (metodo = 'POST' AND ruta = '/api/trabajadores')
    OR (metodo = 'PUT'  AND ruta = '/api/trabajadores/yo/credencial')
    OR (metodo = 'PUT'  AND ruta ~ '^/api/trabajadores/[0-9]+/credencial$');

-- 2) S-27: código de vida corta. El trabajador lo pide a su teléfono (POST
--    /api/trabajadores/yo/credencial/codigo) y el bodeguero lo escanea. Se guarda del lado del
--    servidor, con su expiración: no es un token firmado, así que se puede revocar (renovar la
--    credencial borra los del trabajador) y no hay nada que verificar por fuera de la base.
--
--    `codigo` va normalizado (mayúsculas, sin guiones ni espacios), 8 caracteres de un alfabeto sin
--    ambiguos. Cada pedido emite uno nuevo y los anteriores valen hasta que vencen, por eso un
--    trabajador tiene varios. Los vencidos se conservan un rato para poder decir «caducó» en vez de
--    «no existe», y los poda CodigoCredencialService.
CREATE TABLE codigos_credencial (
    id            BIGSERIAL    PRIMARY KEY,
    trabajador_id BIGINT       NOT NULL REFERENCES trabajadores (id) ON DELETE CASCADE,
    codigo        VARCHAR(8)   NOT NULL,
    creado_en     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expira_en     TIMESTAMPTZ  NOT NULL,
    CONSTRAINT uq_codigos_credencial_codigo UNIQUE (codigo)
);

CREATE INDEX idx_codigos_credencial_trabajador ON codigos_credencial (trabajador_id);
-- La poda borra por vencimiento.
CREATE INDEX idx_codigos_credencial_expira_en ON codigos_credencial (expira_en);
