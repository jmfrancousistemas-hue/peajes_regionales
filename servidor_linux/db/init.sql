-- Base de datos del sistema de peajes regionales
-- Se ejecuta automáticamente la primera vez que arranca el contenedor de PostgreSQL.

CREATE TABLE categorias (
    id          SERIAL PRIMARY KEY,
    codigo      VARCHAR(10)  NOT NULL UNIQUE,
    nombre      VARCHAR(60)  NOT NULL,
    descripcion VARCHAR(160),
    tarifa      INTEGER      NOT NULL CHECK (tarifa > 0)
);

CREATE TABLE taquillas (
    id      INTEGER PRIMARY KEY,
    nombre  VARCHAR(40) NOT NULL,
    tipo    VARCHAR(10) NOT NULL CHECK (tipo IN ('MANUAL', 'TAG')),
    activa  BOOLEAN     NOT NULL DEFAULT TRUE
);

CREATE TABLE tarjetas_tag (
    id            SERIAL PRIMARY KEY,
    numero_tag    VARCHAR(20)  NOT NULL UNIQUE,
    placa         VARCHAR(10)  NOT NULL UNIQUE,
    categoria_id  INTEGER      NOT NULL REFERENCES categorias(id),
    propietario   VARCHAR(100) NOT NULL,
    telefono      VARCHAR(20),
    saldo         INTEGER      NOT NULL DEFAULT 0 CHECK (saldo >= 0),
    activa        BOOLEAN      NOT NULL DEFAULT TRUE,
    creada        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE transacciones (
    id            SERIAL PRIMARY KEY,
    consecutivo   VARCHAR(20)  NOT NULL UNIQUE,
    taquilla_id   INTEGER      NOT NULL REFERENCES taquillas(id),
    placa         VARCHAR(10)  NOT NULL,
    categoria_id  INTEGER      NOT NULL REFERENCES categorias(id),
    valor         INTEGER      NOT NULL,
    medio         VARCHAR(10)  NOT NULL CHECK (medio IN ('EFECTIVO', 'TAG')),
    tarjeta_id    INTEGER      REFERENCES tarjetas_tag(id),
    simulada      BOOLEAN      NOT NULL DEFAULT FALSE,
    fecha         TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_transacciones_fecha ON transacciones(fecha);

CREATE TABLE recargas (
    id               SERIAL PRIMARY KEY,
    tarjeta_id       INTEGER     NOT NULL REFERENCES tarjetas_tag(id),
    valor            INTEGER     NOT NULL CHECK (valor > 0),
    medio_pago       VARCHAR(20) NOT NULL,
    saldo_resultante INTEGER     NOT NULL,
    fecha            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rechazos_tag (
    id          SERIAL PRIMARY KEY,
    referencia  VARCHAR(20) NOT NULL,
    motivo      VARCHAR(80) NOT NULL,
    fecha       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Tarifas de referencia (INVÍAS 2026, las mismas del simulador de MATLAB)
INSERT INTO categorias (codigo, nombre, descripcion, tarifa) VALUES
  ('I',     'Categoría I',     'Automóviles, camperos y camionetas', 10900),
  ('II',    'Categoría II',    'Buses y busetas',                     11800),
  ('III-V', 'Categoría III-V', 'Camiones de 2 a 5 ejes',              25000);

INSERT INTO taquillas (id, nombre, tipo) VALUES
  (1, 'Taquilla 1', 'MANUAL'),
  (2, 'Taquilla 2', 'MANUAL'),
  (3, 'Taquilla 3', 'MANUAL'),
  (4, 'Carril TAG', 'TAG');

-- Tarjetas TAG de prueba (datos ficticios)
INSERT INTO tarjetas_tag (numero_tag, placa, categoria_id, propietario, telefono, saldo) VALUES
  ('TAG-0001', 'ABC123', 1, 'Cooperativa de Transporte - Vehículo 01', '3000000001', 150000),
  ('TAG-0002', 'BUS456', 2, 'Cooperativa de Transporte - Bus 12',      '3000000002',  60000),
  ('TAG-0003', 'TRK789', 3, 'Transportes de Carga del Valle',          '3000000003',  30000),
  ('TAG-0004', 'XYZ987', 1, 'Usuario de prueba saldo bajo',            '3000000004',   8000);

-- Flota que usa la simulación de tráfico (no toca los TAG de la demo)
INSERT INTO tarjetas_tag (numero_tag, placa, categoria_id, propietario, saldo)
SELECT 'SIM-' || lpad(g::text, 3, '0'),
       'SIM' || lpad(g::text, 3, '0'),
       CASE WHEN g % 10 < 7 THEN 1 WHEN g % 10 < 8 THEN 2 ELSE 3 END,
       'Flota simulada ' || g,
       (g * 37000) % 400000
FROM generate_series(1, 30) AS g;
