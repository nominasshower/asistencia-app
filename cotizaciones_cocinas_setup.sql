-- cotizaciones_cocinas_setup.sql — Guardado de cotizaciones de cotizador_cocinas.html en Supabase
-- CÓMO CORRERLO: Supabase Dashboard → SQL Editor → pegar → Run (una sola vez)

CREATE TABLE IF NOT EXISTS cotizaciones_cocinas (
  id           bigserial PRIMARY KEY,
  nombre       text NOT NULL UNIQUE,     -- nombre del proyecto/cotizacion
  persona      text,                     -- quien capturo/guardo la cotizacion
  config       jsonb,                    -- grosor tablero, kerf, margen, rotacion, modo de corte
  gabinetes    jsonb,                    -- modulos de la cocina (medidas capturadas)
  piezas       jsonb,                    -- piezas de tablero generadas/capturadas
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

ALTER TABLE cotizaciones_cocinas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rw publico cotizaciones_cocinas" ON cotizaciones_cocinas;
CREATE POLICY "rw publico cotizaciones_cocinas" ON cotizaciones_cocinas
  FOR ALL USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION set_updated_at_cotizaciones_cocinas()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cotizcocinas_updated_at ON cotizaciones_cocinas;
CREATE TRIGGER trg_cotizcocinas_updated_at
  BEFORE UPDATE ON cotizaciones_cocinas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at_cotizaciones_cocinas();
