-- Corre esto UNA vez antes del script de migración del histórico.
ALTER TABLE inventario_muerto ADD COLUMN IF NOT EXISTS origen_appsheet_id text UNIQUE;
