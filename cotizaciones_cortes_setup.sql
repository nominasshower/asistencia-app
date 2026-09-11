-- cotizaciones_cortes_setup.sql — Guardado de cotizaciones de optimizador_cortes.html en Supabase
-- CÓMO CORRERLO: Supabase Dashboard → SQL Editor → pegar → Run (una sola vez)

CREATE TABLE IF NOT EXISTS cotizaciones_cortes (
  id           bigserial PRIMARY KEY,
  nombre       text NOT NULL UNIQUE,     -- nombre del proyecto/cotizacion
  persona      text,                     -- quien capturo/guardo la cotizacion
  config       jsonb,                    -- kerf, margen, rotacion, modo de corte
  piezas       jsonb,                    -- lista de piezas capturadas
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

-- si la tabla ya existia de una version anterior de este script:
ALTER TABLE cotizaciones_cortes ADD COLUMN IF NOT EXISTS persona text;

ALTER TABLE cotizaciones_cortes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rw publico cotizaciones_cortes" ON cotizaciones_cortes;
CREATE POLICY "rw publico cotizaciones_cortes" ON cotizaciones_cortes
  FOR ALL USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION set_updated_at_cotizaciones_cortes()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cotizcortes_updated_at ON cotizaciones_cortes;
CREATE TRIGGER trg_cotizcortes_updated_at
  BEFORE UPDATE ON cotizaciones_cortes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at_cotizaciones_cortes();
