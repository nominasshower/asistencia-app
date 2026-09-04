-- Corre esto una vez antes de usar el boton "Recuperar".
ALTER TABLE inventario_muerto_movimientos ADD COLUMN IF NOT EXISTS sku_nuevo text;
