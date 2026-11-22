-- Mejora #153 (origen: límite anotado en #76 y PR #129): el control de duplicados de las solicitudes
-- de material vivía solo en la aplicación (existsBy… más el bloqueo del trabajador). Una escritura que
-- se saltara el servicio dejaba dos solicitudes PENDIENTES idénticas. El índice único parcial lo hace
-- cumplir también en la base: un trabajador no puede tener dos pendientes del mismo material en la
-- misma obra. Las aprobadas, rechazadas, entregadas y canceladas no cuentan: se puede volver a pedir.

-- Una base que ya tenga duplicados (el bug #76 los permitía antes de su corrección) haría fallar la
-- creación del índice, y con ella el arranque. Se conserva la pendiente más antigua de cada grupo, que
-- es la que bodega ya veía primero, y las demás pasan a CANCELADA con una nota; no se borra nada.
UPDATE solicitudes_material s
   SET estado = 'CANCELADA',
       motivo_rechazo = 'Duplicada de otra solicitud pendiente (migración V14)'
 WHERE s.estado = 'PENDIENTE'
   AND EXISTS (
       SELECT 1
         FROM solicitudes_material otra
        WHERE otra.estado = 'PENDIENTE'
          AND otra.trabajador_id = s.trabajador_id
          AND otra.material_id = s.material_id
          AND otra.obra_id = s.obra_id
          AND (otra.fecha_solicitud < s.fecha_solicitud
               OR (otra.fecha_solicitud = s.fecha_solicitud AND otra.id < s.id))
   );

CREATE UNIQUE INDEX uq_solicitud_material_pendiente
    ON solicitudes_material (trabajador_id, material_id, obra_id)
 WHERE estado = 'PENDIENTE';
