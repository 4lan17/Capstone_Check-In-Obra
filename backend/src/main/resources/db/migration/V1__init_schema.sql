-- Esquema inicial de Check-In-Obra MVP1, generado a partir del diagrama de
-- clases (Configuración, Obra y equipos, Cubicación, Presupuesto,
-- Inventario y trazabilidad, Control). Orden de creación = orden de
-- dependencia de llaves foráneas.

CREATE TABLE empresas (
    id     BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(200) NOT NULL,
    rut    VARCHAR(20)  NOT NULL UNIQUE
);

CREATE TABLE usuarios (
    id          BIGSERIAL PRIMARY KEY,
    nombre      VARCHAR(200) NOT NULL,
    email       VARCHAR(200) NOT NULL UNIQUE,
    rol         VARCHAR(20)  NOT NULL,
    pin_hash    VARCHAR(100),
    empresa_id  BIGINT       NOT NULL REFERENCES empresas (id)
);

CREATE TABLE obras (
    id          BIGSERIAL PRIMARY KEY,
    nombre      VARCHAR(200) NOT NULL,
    cliente     VARCHAR(200) NOT NULL,
    ubicacion   VARCHAR(300) NOT NULL,
    estado      VARCHAR(20)  NOT NULL,
    empresa_id  BIGINT       NOT NULL REFERENCES empresas (id)
);

CREATE TABLE cuadrillas (
    id       BIGSERIAL PRIMARY KEY,
    nombre   VARCHAR(200) NOT NULL,
    obra_id  BIGINT       NOT NULL REFERENCES obras (id)
);

CREATE TABLE trabajadores (
    id             BIGSERIAL PRIMARY KEY,
    rut            VARCHAR(20)  NOT NULL UNIQUE,
    credencial_qr  VARCHAR(100) UNIQUE,
    usuario_id     BIGINT       NOT NULL UNIQUE REFERENCES usuarios (id),
    cuadrilla_id   BIGINT       REFERENCES cuadrillas (id)
);

CREATE TABLE materiales (
    id              BIGSERIAL PRIMARY KEY,
    sku             VARCHAR(50)  NOT NULL UNIQUE,
    nombre          VARCHAR(200) NOT NULL,
    categoria       VARCHAR(20)  NOT NULL,
    precio_unitario DOUBLE PRECISION NOT NULL,
    stock_minimo    DOUBLE PRECISION NOT NULL,
    empresa_id      BIGINT       NOT NULL REFERENCES empresas (id)
);

CREATE TABLE parametros_merma (
    id          BIGSERIAL PRIMARY KEY,
    porcentaje  DOUBLE PRECISION NOT NULL,
    material_id BIGINT NOT NULL UNIQUE REFERENCES materiales (id)
);

CREATE TABLE partidas (
    id                    BIGSERIAL PRIMARY KEY,
    tipo                  VARCHAR(20) NOT NULL,
    ancho_m               DOUBLE PRECISION NOT NULL,
    alto_m                DOUBLE PRECISION NOT NULL,
    separacion_montantes  DOUBLE PRECISION NOT NULL,
    obra_id               BIGINT NOT NULL REFERENCES obras (id)
);

CREATE TABLE items_cubicados (
    id                   BIGSERIAL PRIMARY KEY,
    cantidad_calculada   DOUBLE PRECISION NOT NULL,
    cantidad_con_merma   DOUBLE PRECISION NOT NULL,
    partida_id           BIGINT NOT NULL REFERENCES partidas (id),
    material_id          BIGINT NOT NULL REFERENCES materiales (id)
);

CREATE TABLE presupuestos (
    id               BIGSERIAL PRIMARY KEY,
    estado           VARCHAR(20) NOT NULL,
    fecha_congelado  DATE,
    total            DOUBLE PRECISION NOT NULL,
    obra_id          BIGINT NOT NULL UNIQUE REFERENCES obras (id)
);

CREATE TABLE presupuesto_items (
    id               BIGSERIAL PRIMARY KEY,
    cantidad         DOUBLE PRECISION NOT NULL,
    precio_unitario  DOUBLE PRECISION NOT NULL,
    subtotal         DOUBLE PRECISION NOT NULL,
    presupuesto_id   BIGINT NOT NULL REFERENCES presupuestos (id),
    material_id      BIGINT NOT NULL REFERENCES materiales (id)
);

CREATE TABLE herramientas (
    id                BIGSERIAL PRIMARY KEY,
    codigo_qr         VARCHAR(100) NOT NULL UNIQUE,
    nombre            VARCHAR(200) NOT NULL,
    categoria         VARCHAR(100) NOT NULL,
    estado            VARCHAR(20)  NOT NULL,
    valor_reposicion  DOUBLE PRECISION NOT NULL,
    empresa_id        BIGINT NOT NULL REFERENCES empresas (id)
);

CREATE TABLE prestamos_herramienta (
    id                     BIGSERIAL PRIMARY KEY,
    fecha_prestamo         TIMESTAMP NOT NULL,
    fecha_devol_esperada   TIMESTAMP NOT NULL,
    fecha_devol_real       TIMESTAMP,
    herramienta_id         BIGINT NOT NULL REFERENCES herramientas (id),
    trabajador_id          BIGINT NOT NULL REFERENCES trabajadores (id),
    obra_id                BIGINT NOT NULL REFERENCES obras (id),
    autorizado_por_id      BIGINT NOT NULL REFERENCES usuarios (id)
);

CREATE TABLE kardex_movimientos (
    id               BIGSERIAL PRIMARY KEY,
    tipo_movimiento  VARCHAR(20) NOT NULL,
    cantidad         DOUBLE PRECISION NOT NULL,
    fecha            TIMESTAMP NOT NULL,
    obra_id          BIGINT NOT NULL REFERENCES obras (id),
    material_id      BIGINT NOT NULL REFERENCES materiales (id),
    usuario_id       BIGINT NOT NULL REFERENCES usuarios (id)
);

CREATE TABLE solicitudes_herramienta (
    id                BIGSERIAL PRIMARY KEY,
    cantidad          INTEGER NOT NULL,
    estado            VARCHAR(20) NOT NULL,
    fecha_solicitud   TIMESTAMP NOT NULL,
    motivo_rechazo    VARCHAR(500),
    trabajador_id     BIGINT NOT NULL REFERENCES trabajadores (id),
    herramienta_id    BIGINT NOT NULL REFERENCES herramientas (id),
    resuelto_por_id   BIGINT REFERENCES usuarios (id)
);

CREATE TABLE solicitudes_material (
    id                BIGSERIAL PRIMARY KEY,
    cantidad          DOUBLE PRECISION NOT NULL,
    estado            VARCHAR(20) NOT NULL,
    fecha_solicitud   TIMESTAMP NOT NULL,
    motivo_rechazo    VARCHAR(500),
    trabajador_id     BIGINT NOT NULL REFERENCES trabajadores (id),
    material_id       BIGINT NOT NULL REFERENCES materiales (id),
    obra_id           BIGINT NOT NULL REFERENCES obras (id),
    resuelto_por_id   BIGINT REFERENCES usuarios (id)
);

CREATE TABLE alertas (
    id                        BIGSERIAL PRIMARY KEY,
    tipo                      VARCHAR(20) NOT NULL,
    mensaje                   VARCHAR(500) NOT NULL,
    fecha                     TIMESTAMP NOT NULL,
    resuelto                  BOOLEAN NOT NULL,
    obra_id                   BIGINT NOT NULL REFERENCES obras (id),
    prestamo_herramienta_id   BIGINT REFERENCES prestamos_herramienta (id)
);

CREATE INDEX idx_kardex_obra_material ON kardex_movimientos (obra_id, material_id);
CREATE INDEX idx_prestamo_obra_abierto ON prestamos_herramienta (obra_id, fecha_devol_real);
CREATE INDEX idx_solicitud_herr_trabajador ON solicitudes_herramienta (trabajador_id);
CREATE INDEX idx_solicitud_mat_obra ON solicitudes_material (obra_id);
CREATE INDEX idx_alertas_obra_resuelto ON alertas (obra_id, resuelto);
