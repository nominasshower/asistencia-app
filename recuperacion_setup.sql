-- recuperacion_setup.sql — App Recuperación de Piezas
-- CÓMO CORRERLO: Supabase Dashboard → SQL Editor → pegar → Run

CREATE TABLE IF NOT EXISTS recuperaciones (
  id           bigserial PRIMARY KEY,
  pedido       text NOT NULL,
  cliente      text,
  producto     text,
  sku_producto text,
  cant_solicitada int NOT NULL DEFAULT 1,
  cant_recuperada int NOT NULL DEFAULT 0,
  estado       text NOT NULL DEFAULT 'pendiente',  -- pendiente | parcial | completada | cancelada
  notas        text,
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS recuperaciones_piezas (
  id               bigserial PRIMARY KEY,
  recuperacion_id  bigint NOT NULL REFERENCES recuperaciones(id),
  sku              text NOT NULL UNIQUE,
  escaneado_at     timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_recup_estado ON recuperaciones (estado);
CREATE INDEX IF NOT EXISTS idx_recup_pzas ON recuperaciones_piezas (recuperacion_id);

ALTER TABLE recuperaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE recuperaciones_piezas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rw publico recuperaciones" ON recuperaciones;
CREATE POLICY "rw publico recuperaciones" ON recuperaciones
  FOR ALL USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "rw publico recuperaciones_piezas" ON recuperaciones_piezas;
CREATE POLICY "rw publico recuperaciones_piezas" ON recuperaciones_piezas
  FOR ALL USING (true) WITH CHECK (true);
