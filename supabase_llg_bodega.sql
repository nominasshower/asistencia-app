-- ============================================================
-- LLG (bodega Laredo): entrada y salida de burritos
-- Pagina: llg_bodega.html (escanea etiqueta de calidad, lado A o lado B;
-- las 3 traen el mismo uuid del burrito, los lados con sufijo A/B).
-- Ejecutar en Supabase > SQL Editor. NO toca tablas existentes.
-- ============================================================

-- 1) Estado por burrito: una fila por uuid con su fecha de llegada y de salida.
--    orden/cliente/po/tipo/piezas se copian de `burritos` al escanear, para que
--    la fila conserve su Q aunque el burrito se borre despues en ConnectIT.
create table if not exists public.llg_burritos (
  package_uuid  text primary key,
  orden         text,
  cliente       text,
  po_cliente    text,
  tipo_paquete  text,
  piezas        integer,
  entrada_en    timestamptz,
  entrada_por   text,
  salida_en     timestamptz,
  salida_por    text,
  actualizado_en timestamptz not null default now()
);
create index if not exists llg_burritos_orden_idx on public.llg_burritos (orden);

-- 2) Bitacora: cada vez que tocan Llego/Salio queda un renglon (control y correcciones).
create table if not exists public.llg_movimientos (
  id            bigint generated always as identity primary key,
  package_uuid  text not null,
  orden         text,
  tipo          text not null check (tipo in ('entrada','salida')),
  fecha         timestamptz not null default now(),
  escaneado_por text,
  codigo_leido  text,           -- lo que leyo el escaner tal cual (con A/B si fue lado)
  reemplazo     boolean not null default false  -- true si sobrescribio una fecha ya registrada
);
create index if not exists llg_movimientos_fecha_idx on public.llg_movimientos (fecha desc);
create index if not exists llg_movimientos_uuid_idx  on public.llg_movimientos (package_uuid);

-- actualizado_en se mantiene solo
create or replace function public.llg_touch() returns trigger language plpgsql as $$
begin new.actualizado_en := now(); return new; end $$;
drop trigger if exists llg_burritos_touch on public.llg_burritos;
create trigger llg_burritos_touch before update on public.llg_burritos
  for each row execute function public.llg_touch();

-- 3) Vista por Q (la que consulta Odoo): primera llegada y ultima salida de cada orden.
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
       sum(piezas)                       as piezas
from public.llg_burritos
group by orden;

-- 4) Permisos para la llave publica: leer, insertar y actualizar. SIN borrar.
alter table public.llg_burritos    enable row level security;
alter table public.llg_movimientos enable row level security;

drop policy if exists "llg_select" on public.llg_burritos;
drop policy if exists "llg_insert" on public.llg_burritos;
drop policy if exists "llg_update" on public.llg_burritos;
create policy "llg_select" on public.llg_burritos for select to anon using (true);
create policy "llg_insert" on public.llg_burritos for insert to anon with check (true);
create policy "llg_update" on public.llg_burritos for update to anon using (true) with check (true);

drop policy if exists "llg_mov_select" on public.llg_movimientos;
drop policy if exists "llg_mov_insert" on public.llg_movimientos;
create policy "llg_mov_select" on public.llg_movimientos for select to anon using (true);
create policy "llg_mov_insert" on public.llg_movimientos for insert to anon with check (true);

grant select, insert, update on public.llg_burritos    to anon;
grant select, insert         on public.llg_movimientos to anon;
grant select                 on public.llg_por_orden   to anon;

-- 5) Verificar: debe listar las 2 tablas con rls_activo = true y la vista.
select c.relname, c.relkind, c.relrowsecurity as rls_activo
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname like 'llg_%' order by 1;
