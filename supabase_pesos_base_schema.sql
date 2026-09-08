-- NUEVO — no toca ninguna tabla existente (vaciados, rh.*, etc.)
-- Tabla de referencia: peso real/estimado por modelo+medida de BASE.
-- Se cruza con `vaciados` (tipo='Piso') por patron+medida para armar el
-- reporte de piezas vaciadas con peso. Correr una sola vez en el SQL editor
-- de Supabase (proyecto xzwlbrirzfogbqhywtvj, schema public).

CREATE TABLE IF NOT EXISTS public.pesos_base (
    id              bigint generated always as identity primary key,
    patron          text NOT NULL,          -- ej. "BASE CENTER DRAIN (CD) CENTER" (mismo texto que vaciados.patron)
    medida          text NOT NULL,          -- ej. "34x48" (mismo formato que vaciados.medida, minusculas)
    ancho_in        numeric,
    largo_in        numeric,
    peso_kg         numeric NOT NULL,       -- valor que usa el reporte
    peso_kg_min     numeric,
    peso_kg_max     numeric,
    n_muestras      int DEFAULT 1,
    fuente          text NOT NULL CHECK (fuente IN ('medido_planta','solidworks','calculado_plano','estimado')),
    confianza       text CHECK (confianza IN ('alta','media','baja')),
    fecha_actualizado timestamptz DEFAULT now(),
    notas           text,
    UNIQUE (patron, medida)
);

COMMENT ON TABLE public.pesos_base IS
  'Peso por modelo+medida de base, para el reporte de piezas vaciadas con peso. Tabla nueva, independiente de vaciados/recuperacion_log.';
