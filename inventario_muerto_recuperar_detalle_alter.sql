-- Corre esto una vez para guardar el detalle completo de cada recuperacion
-- (pedido destino + modelo/medida antes y despues), asi el reporte de
-- Piezas Recuperadas no depende de cruzar tablas despues.
ALTER TABLE inventario_muerto_movimientos
  ADD COLUMN IF NOT EXISTS pedido text,
  ADD COLUMN IF NOT EXISTS modelo_viejo text,
  ADD COLUMN IF NOT EXISTS color_viejo text,
  ADD COLUMN IF NOT EXISTS medida_vieja text,
  ADD COLUMN IF NOT EXISTS modelo_nuevo text,
  ADD COLUMN IF NOT EXISTS color_nuevo text,
  ADD COLUMN IF NOT EXISTS medida_nueva text,
  ADD COLUMN IF NOT EXISTS acabado_nuevo text;
