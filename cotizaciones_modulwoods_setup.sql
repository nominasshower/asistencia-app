-- cotizaciones_modulwoods_setup.sql — Guardado de cotizaciones de cotizador_modulwoods.html en Supabase
-- CÓMO CORRERLO: Supabase Dashboard → SQL Editor → pegar → Run (una sola vez)

CREATE TABLE IF NOT EXISTS cotizaciones_modulwoods (
  id           bigserial PRIMARY KEY,
  nombre       text NOT NULL UNIQUE,     -- nombre del proyecto
  cliente      text,
  persona      text,                     -- quien capturo/guardo la cotizacion
  n_gabinetes  int,
  total_usd    numeric,
  datos        jsonb,                    -- gabinetes, extras, precios usados, margenes, corredera, etc.
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

ALTER TABLE cotizaciones_modulwoods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rw publico cotizaciones_modulwoods" ON cotizaciones_modulwoods;
CREATE POLICY "rw publico cotizaciones_modulwoods" ON cotizaciones_modulwoods
  FOR ALL USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION set_updated_at_cotizaciones_modulwoods()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cotizmw_updated_at ON cotizaciones_modulwoods;
CREATE TRIGGER trg_cotizmw_updated_at
  BEFORE UPDATE ON cotizaciones_modulwoods
  FOR EACH ROW EXECUTE FUNCTION set_updated_at_cotizaciones_modulwoods();
