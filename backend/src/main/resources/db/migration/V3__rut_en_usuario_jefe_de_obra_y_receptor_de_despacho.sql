-- Tres huecos del modelo que aparecieron al construir la vista del bodeguero.

-- 1. El RUT identifica a una PERSONA, no a un rol.
--
-- Estaba solo en `trabajadores`, y un jefe de terreno es un `usuario` sin
-- registro de trabajador (TrabajadorService rechaza cualquier rol que no sea
-- TRABAJADOR). Es decir: no había dónde guardar el RUT de un jefe de obra ni
-- el de un bodeguero. Se sube a `usuarios`, que es la clase que representa a
-- la persona, y se deja de duplicar.
ALTER TABLE usuarios ADD COLUMN rut VARCHAR(20);

UPDATE usuarios u
SET rut = t.rut
FROM trabajadores t
WHERE t.usuario_id = u.id;

ALTER TABLE usuarios ADD CONSTRAINT uq_usuarios_rut UNIQUE (rut);

-- Queda NULL para los usuarios anteriores a esta migración (el admin semilla).
-- La API sí lo exige al crear usuarios nuevos.
ALTER TABLE trabajadores DROP COLUMN rut;

-- 2. Quién dirige la obra.
--
-- El mockup AdminObras ya tenía una columna "JEFE DE TERRENO" que el modelo
-- nunca modeló. Nullable: una obra puede existir antes de que se le asigne
-- jefe.
ALTER TABLE obras ADD COLUMN jefe_terreno_id BIGINT REFERENCES usuarios (id);

-- 3. A quién se le entregó el material.
--
-- `kardex_movimientos` registraba quién ANOTA el movimiento (usuario_id), no
-- quién RECIBE. Para un despacho son dos personas distintas: el bodeguero que
-- lo registra y el trabajador que se lleva el material. Sin esta columna, el
-- kardex no puede responder "¿a quién se le entregaron esas 36 planchas?".
--
-- Nullable porque una RECEPCION no tiene receptor: el material entra desde un
-- proveedor, no desde un trabajador.
ALTER TABLE kardex_movimientos ADD COLUMN trabajador_id BIGINT REFERENCES trabajadores (id);

CREATE INDEX idx_kardex_trabajador ON kardex_movimientos (trabajador_id);
