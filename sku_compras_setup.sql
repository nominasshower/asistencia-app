-- sku_compras_setup.sql — tablas del Generador de SKU de Compras (sku_compras.html)
-- CÓMO CORRERLO: Supabase Dashboard → SQL Editor → pegar → Run (una sola vez).
-- Después correr sku_compras_seed.sql (catálogo + SKUs que ya existen en Odoo).

CREATE TABLE IF NOT EXISTS sku_catalogo (
  codigo          text PRIMARY KEY,           -- prefijo TI-MOD, ej. 'MP-10'
  familia         text NOT NULL,
  subfamilia      text NOT NULL,
  categoria_odoo  text,                       -- categoría que ya usan en Odoo los artículos de este código
  descripcion     text,                       -- nota libre para distinguir códigos de la misma subfamilia
  orden           int  DEFAULT 0,
  activo          boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS sku_articulos (
  id           bigserial PRIMARY KEY,
  sku          text NOT NULL UNIQUE,
  codigo       text NOT NULL REFERENCES sku_catalogo(codigo),
  consecutivo  int  NOT NULL,
  nombre       text NOT NULL,
  um           text,
  empresa      text,
  origen       text NOT NULL DEFAULT 'HERRAMIENTA',   -- 'ODOO' = ya existía al sembrar; 'HERRAMIENTA' = generado aquí
  en_odoo      boolean NOT NULL DEFAULT false,         -- ya se capturó manualmente en Odoo
  creado_por   text,
  notas        text,
  created_at   timestamptz DEFAULT now(),
  UNIQUE (codigo, consecutivo)
);
CREATE INDEX IF NOT EXISTS sku_articulos_codigo_idx ON sku_articulos (codigo);

-- Asigna el consecutivo de forma atómica (dos personas al mismo tiempo no pueden sacar el mismo SKU).
-- p_numero NULL = siguiente número libre de la secuencia normal (< 1000);
-- p_numero con valor = número específico (ej. códigos por medida como EM-03-3018), valida que esté libre.
CREATE OR REPLACE FUNCTION generar_sku(
  p_codigo text, p_nombre text, p_um text, p_empresa text,
  p_creado_por text, p_notas text, p_numero int DEFAULT NULL
) RETURNS sku_articulos
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  n int;
  r sku_articulos;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM sku_catalogo WHERE codigo = p_codigo AND activo) THEN
    RAISE EXCEPTION 'El código % no existe en el catálogo', p_codigo;
  END IF;
  IF coalesce(trim(p_nombre), '') = '' THEN
    RAISE EXCEPTION 'Falta el nombre del artículo';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('sku:' || p_codigo));

  IF p_numero IS NOT NULL THEN
    IF p_numero < 1 OR p_numero > 9999 THEN
      RAISE EXCEPTION 'El número debe estar entre 1 y 9999';
    END IF;
    IF EXISTS (SELECT 1 FROM sku_articulos WHERE codigo = p_codigo AND consecutivo = p_numero) THEN
      RAISE EXCEPTION 'El SKU %-% ya está ocupado', p_codigo, lpad(p_numero::text, 4, '0');
    END IF;
    n := p_numero;
  ELSE
    SELECT coalesce(max(consecutivo), 0) + 1 INTO n
      FROM sku_articulos WHERE codigo = p_codigo AND consecutivo < 1000;
    WHILE EXISTS (SELECT 1 FROM sku_articulos WHERE codigo = p_codigo AND consecutivo = n) LOOP
      n := n + 1;
    END LOOP;
  END IF;

  INSERT INTO sku_articulos (sku, codigo, consecutivo, nombre, um, empresa, origen, creado_por, notas)
  VALUES (p_codigo || '-' || lpad(n::text, 4, '0'), p_codigo, n, upper(trim(p_nombre)),
          nullif(trim(p_um), ''), nullif(trim(p_empresa), ''), 'HERRAMIENTA',
          nullif(trim(p_creado_por), ''), nullif(trim(p_notas), ''))
  RETURNING * INTO r;
  RETURN r;
END;
$$;

-- Lectura libre; las altas solo pasan por generar_sku(); se permite marcar "ya en Odoo"; nadie borra desde la página.
ALTER TABLE sku_catalogo  ENABLE ROW LEVEL SECURITY;
ALTER TABLE sku_articulos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "leer sku_catalogo" ON sku_catalogo;
CREATE POLICY "leer sku_catalogo" ON sku_catalogo FOR SELECT USING (true);
DROP POLICY IF EXISTS "leer sku_articulos" ON sku_articulos;
CREATE POLICY "leer sku_articulos" ON sku_articulos FOR SELECT USING (true);
DROP POLICY IF EXISTS "marcar sku_articulos" ON sku_articulos;
CREATE POLICY "marcar sku_articulos" ON sku_articulos FOR UPDATE USING (origen = 'HERRAMIENTA') WITH CHECK (origen = 'HERRAMIENTA');

REVOKE UPDATE ON sku_articulos FROM anon, authenticated;
GRANT  UPDATE (en_odoo) ON sku_articulos TO anon, authenticated;
GRANT  EXECUTE ON FUNCTION generar_sku(text, text, text, text, text, text, int) TO anon, authenticated;
