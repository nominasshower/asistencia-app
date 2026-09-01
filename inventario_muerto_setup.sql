-- inventario_muerto_setup.sql — App Inventario Muerto (reemplaza AppSheet + Google Sheets)
-- CÓMO CORRERLO: Supabase Dashboard → SQL Editor → pegar → Run
-- Luego crear el bucket de Storage "inventario-muerto-fotos" (público) desde el dashboard.

CREATE TABLE IF NOT EXISTS inventario_muerto (
  id             bigserial PRIMARY KEY,
  burrito        text,
  pieza          text NOT NULL,
  modelo         text,
  color          text,
  ancho          numeric,
  alto           numeric,
  medidas        text,
  acabado        text,                                   -- MATE | BRILLO
  linea          text,                                   -- LINEA 1 | LINEA 2 | Sin Linea
  tag            text,                                    -- para cuando se conecte RFID
  tipo_entrada   text,                                    -- CORTE | RECUPERADA | ...
  foto_etiqueta_url text,
  estatus        text NOT NULL DEFAULT 'EN INVENTARIO',   -- EN INVENTARIO | EN STOCK | EN PATIO | GRADO C | SALIDA MUESTRA
  notas          text,
  created_at     timestamptz DEFAULT now(),
  updated_at     timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS inventario_muerto_movimientos (
  id               bigserial PRIMARY KEY,
  inventario_id    bigint NOT NULL REFERENCES inventario_muerto(id),
  estatus_anterior text,
  estatus_nuevo    text NOT NULL,
  usuario          text,
  created_at       timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invmuerto_estatus ON inventario_muerto (estatus);
CREATE INDEX IF NOT EXISTS idx_invmuerto_pieza ON inventario_muerto (pieza);
CREATE INDEX IF NOT EXISTS idx_invmuerto_mov_inv ON inventario_muerto_movimientos (inventario_id);

ALTER TABLE inventario_muerto ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario_muerto_movimientos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rw publico inventario_muerto" ON inventario_muerto;
CREATE POLICY "rw publico inventario_muerto" ON inventario_muerto
  FOR ALL USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "rw publico inventario_muerto_movimientos" ON inventario_muerto_movimientos;
CREATE POLICY "rw publico inventario_muerto_movimientos" ON inventario_muerto_movimientos
  FOR ALL USING (true) WITH CHECK (true);

-- trigger simple para updated_at
CREATE OR REPLACE FUNCTION set_updated_at_inventario_muerto()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invmuerto_updated_at ON inventario_muerto;
CREATE TRIGGER trg_invmuerto_updated_at
  BEFORE UPDATE ON inventario_muerto
  FOR EACH ROW EXECUTE FUNCTION set_updated_at_inventario_muerto();
