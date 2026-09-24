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
  id                  bigserial PRIMARY KEY,
  sku                 text NOT NULL UNIQUE,
  codigo              text NOT NULL REFERENCES sku_catalogo(codigo),
  consecutivo         int  NOT NULL,
  nombre              text NOT NULL,
  um                  text,
  empresa             text,
  tipo_producto       text NOT NULL DEFAULT 'ALMACENABLE',  -- ALMACENABLE | CONSUMIBLE | SERVICIO
  precio_estandar     numeric,
  moneda              text DEFAULT 'MN',                    -- MN | USD
  sustancia_peligrosa boolean NOT NULL DEFAULT false,        -- requiere ficha técnica / hoja de seguridad
  origen              text NOT NULL DEFAULT 'HERRAMIENTA',   -- 'ODOO' = ya existía al sembrar; 'HERRAMIENTA' = generado aquí
  en_odoo             boolean NOT NULL DEFAULT false,        -- ya se capturó manualmente en Odoo
  ficha_tecnica_url   text,                                  -- PDF ficha técnica / hoja de seguridad en Storage
  creado_por          text,
  notas               text,
  created_at          timestamptz DEFAULT now(),
  UNIQUE (codigo, consecutivo)
);
CREATE INDEX IF NOT EXISTS sku_articulos_codigo_idx ON sku_articulos (codigo);

-- Si la tabla ya existía de una versión anterior de este script:
ALTER TABLE sku_articulos ADD COLUMN IF NOT EXISTS tipo_producto       text NOT NULL DEFAULT 'ALMACENABLE';
ALTER TABLE sku_articulos ADD COLUMN IF NOT EXISTS precio_estandar     numeric;
ALTER TABLE sku_articulos ADD COLUMN IF NOT EXISTS moneda              text DEFAULT 'MN';
ALTER TABLE sku_articulos ADD COLUMN IF NOT EXISTS sustancia_peligrosa boolean NOT NULL DEFAULT false;
ALTER TABLE sku_articulos ADD COLUMN IF NOT EXISTS ficha_tecnica_url   text;

-- Bucket para PDFs de ficha técnica / hoja de seguridad (público de lectura, cualquiera puede subir).
INSERT INTO storage.buckets (id, name, public)
  VALUES ('sku-fichas', 'sku-fichas', true) ON CONFLICT (id) DO NOTHING;
DROP POLICY IF EXISTS "leer fichas sku" ON storage.objects;
CREATE POLICY "leer fichas sku" ON storage.objects FOR SELECT USING (bucket_id = 'sku-fichas');
DROP POLICY IF EXISTS "subir fichas sku" ON storage.objects;
CREATE POLICY "subir fichas sku" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'sku-fichas');

-- Asigna el consecutivo de forma atómica (dos personas al mismo tiempo no pueden sacar el mismo SKU).
-- p_numero NULL = siguiente número libre de la secuencia normal (< 1000);
-- p_numero con valor = número específico (ej. códigos por medida como EM-03-3018), valida que esté libre.
DROP FUNCTION IF EXISTS generar_sku(text, text, text, text, text, text, int);
DROP FUNCTION IF EXISTS generar_sku(text, text, text, text, text, text, int, text, numeric, text, boolean);

CREATE OR REPLACE FUNCTION generar_sku(
  p_codigo text, p_nombre text, p_um text, p_empresa text,
  p_creado_por text, p_notas text, p_numero int DEFAULT NULL,
  p_tipo_producto text DEFAULT 'ALMACENABLE', p_precio numeric DEFAULT NULL,
  p_moneda text DEFAULT 'MN', p_peligrosa boolean DEFAULT false,
  p_ficha_url text DEFAULT NULL
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
  IF p_tipo_producto NOT IN ('ALMACENABLE', 'CONSUMIBLE', 'SERVICIO') THEN
    RAISE EXCEPTION 'Tipo de producto inválido: %', p_tipo_producto;
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

  INSERT INTO sku_articulos (sku, codigo, consecutivo, nombre, um, empresa, tipo_producto,
                              precio_estandar, moneda, sustancia_peligrosa, ficha_tecnica_url, origen, creado_por, notas)
  VALUES (p_codigo || '-' || lpad(n::text, 4, '0'), p_codigo, n, upper(trim(p_nombre)),
          nullif(trim(p_um), ''), nullif(trim(p_empresa), ''), p_tipo_producto,
          p_precio, nullif(trim(p_moneda), ''), p_peligrosa, nullif(trim(p_ficha_url), ''), 'HERRAMIENTA',
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
DROP POLICY IF EXISTS "actualizar campos permitidos sku_articulos" ON sku_articulos;
-- La fila que se puede tocar la restringe esta policy; QUÉ columna se puede tocar lo restringen los GRANT de abajo:
-- 'en_odoo' solo en artículos generados aquí; 'ficha_tecnica_url' en cualquier artículo (incluidos los ya de Odoo).
CREATE POLICY "actualizar campos permitidos sku_articulos" ON sku_articulos FOR UPDATE USING (true) WITH CHECK (true);

REVOKE UPDATE ON sku_articulos FROM anon, authenticated;
GRANT  UPDATE (en_odoo, ficha_tecnica_url) ON sku_articulos TO anon, authenticated;
GRANT  EXECUTE ON FUNCTION generar_sku(text, text, text, text, text, text, int, text, numeric, text, boolean, text) TO anon, authenticated;
