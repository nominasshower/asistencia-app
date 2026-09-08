-- NUEVO — no toca vaciados, pesos_base ni recuperacion_log (ese sigue solo en ares).
-- Cache liviano de que SKUs pasaron por la Estacion de Recuperacion, para que
-- la pagina piezas_vaciadas_peso.html (GitHub Pages, HTTPS) pueda excluirlos
-- sin llamar directo a ares (HTTP, LAN-only -- bloqueado por mixed-content).
-- Se llena con sync_recuperacion_log.py.

CREATE TABLE IF NOT EXISTS public.recuperacion_skus (
    sku          text PRIMARY KEY,
    fecha        timestamptz NOT NULL,
    synced_at    timestamptz DEFAULT now()
);

COMMENT ON TABLE public.recuperacion_skus IS
  'Cache de SKUs que pasaron por recuperacion_log (ares), para excluirlos del reporte de piezas vaciadas con peso desde el frontend estatico.';
