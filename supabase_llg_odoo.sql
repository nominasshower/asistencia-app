-- ============================================================
-- LLG -> Odoo: vista lista para llenar sale.order
--   arrival_laredo_date        (Odoo: "Arrival Laredo Date",       tipo date)
--   pickup_from_laredo_date    (Odoo: "Pickup From Laredo Date",   tipo date)
-- Solo crea/actualiza vistas de LECTURA. No toca datos.
-- Las fechas se convierten a hora de Laredo (America/Chicago), porque los campos de
-- Odoo son fecha sin hora y la bodega esta en Laredo; en UTC una salida de la tarde
-- podria caer al dia siguiente.
-- ============================================================

-- 1) llg_por_orden con una columna mas al final (para pedir solo lo que cambio)
create or replace view public.llg_por_orden as
select orden,
       max(cliente)    as cliente,
       max(po_cliente) as po_cliente,
       count(*)                          as burritos_escaneados,
       count(entrada_en)                 as burritos_llegados,
       count(salida_en)                  as burritos_salidos,
       min(entrada_en)                   as primera_llegada,
       max(entrada_en)                   as ultima_llegada,
       max(salida_en)                    as ultima_salida,
       sum(piezas)                       as piezas,
       max(actualizado_en)               as ultima_actualizacion
from public.llg_burritos
group by orden;

-- 2) La vista para Odoo: una fila por Q, con las fechas ya en el formato del campo
create or replace view public.llg_para_odoo as
select orden                                                              as q,
       (primera_llegada at time zone 'America/Chicago')::date             as arrival_laredo_date,
       case when burritos_llegados > 0 and burritos_salidos >= burritos_llegados
            then (ultima_salida at time zone 'America/Chicago')::date end as pickup_from_laredo_date,
       burritos_llegados, burritos_salidos, burritos_escaneados,
       ultima_actualizacion
from public.llg_por_orden
where orden is not null and burritos_llegados > 0;

grant select on public.llg_por_orden to anon;
grant select on public.llg_para_odoo to anon;

-- 3) Probar (debe regresar las Q con movimientos; vacio si ya borraste las pruebas)
select * from public.llg_para_odoo order by ultima_actualizacion desc limit 10;
