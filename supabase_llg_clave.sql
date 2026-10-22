-- ============================================================
-- LLG: clave de acceso unica (sin usuarios de Supabase).
-- Sin la clave correcta, nadie puede dar Llego/Salio, ni desde la pagina
-- ni llamando directo a Supabase. Leer (Odoo, reporte) sigue igual.
--
-- ORDEN:
--   PARTE 1 (segura, se puede correr ya): crea la clave y las funciones nuevas.
--           La pagina actual sigue funcionando.
--   [Claude publica la pagina nueva con clave]
--   PARTE 2 (cierre): quita la escritura sin clave. Correr solo despues de publicar.
-- ============================================================

-- ---------- PARTE 1 ----------
-- Cambia 'PON_AQUI_LA_CLAVE' (aparece una sola vez, en el insert de abajo) por la clave que le
-- vas a dar a LLG. Usa 8 o mas caracteres. En Supabase se guarda solo su huella, no la clave.
create table if not exists public.llg_config (
  id int primary key check (id = 1),
  clave_hash text not null
);
alter table public.llg_config enable row level security;      -- sin politicas ni permisos: nadie la lee por la API
revoke all on public.llg_config from anon, authenticated;

insert into public.llg_config (id, clave_hash)
values (1, encode(sha256(convert_to('PON_AQUI_LA_CLAVE' || 'llg-bodega', 'utf8')), 'hex'))
on conflict (id) do update set clave_hash = excluded.clave_hash;

create or replace function public.llg_clave_ok(p_clave text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from public.llg_config
                 where id = 1 and clave_hash = encode(sha256(convert_to(coalesce(p_clave,'') || 'llg-bodega', 'utf8')), 'hex'));
$$;

create or replace function public.llg_validar_clave(p_clave text) returns boolean
language sql security definer set search_path = public as $$
  select public.llg_clave_ok(p_clave);
$$;
grant execute on function public.llg_validar_clave(text) to anon;
revoke execute on function public.llg_clave_ok(text) from anon, public;

-- Nueva version de llg_marcar: pide la clave y corre con permisos propios (security definer)
create or replace function public.llg_marcar(
  p_uuid text, p_tipo text, p_por text, p_codigo text,
  p_orden text, p_cliente text, p_po text, p_tipo_paquete text, p_piezas integer, p_clave text
) returns public.llg_burritos
language plpgsql security definer set search_path = public as $$
declare
  ahora timestamptz := now();
  previo timestamptz;
  fila public.llg_burritos;
begin
  if not public.llg_clave_ok(p_clave) then
    raise exception 'clave_invalida' using errcode = '28000';
  end if;
  if p_tipo not in ('entrada','salida') then raise exception 'tipo invalido: %', p_tipo; end if;
  if p_uuid !~ '^[0-9a-f]{12}$' then raise exception 'uuid invalido: %', p_uuid; end if;

  select case when p_tipo = 'entrada' then entrada_en else salida_en end
    into previo from public.llg_burritos where package_uuid = p_uuid;

  insert into public.llg_burritos as b
    (package_uuid, orden, cliente, po_cliente, tipo_paquete, piezas,
     entrada_en, entrada_por, salida_en, salida_por)
  values
    (p_uuid, p_orden, p_cliente, p_po, p_tipo_paquete, p_piezas,
     case when p_tipo = 'entrada' then ahora end, case when p_tipo = 'entrada' then p_por end,
     case when p_tipo = 'salida'  then ahora end, case when p_tipo = 'salida'  then p_por end)
  on conflict (package_uuid) do update set
    orden        = coalesce(excluded.orden, b.orden),
    cliente      = coalesce(excluded.cliente, b.cliente),
    po_cliente   = coalesce(excluded.po_cliente, b.po_cliente),
    tipo_paquete = coalesce(excluded.tipo_paquete, b.tipo_paquete),
    piezas       = coalesce(excluded.piezas, b.piezas),
    entrada_en   = case when p_tipo = 'entrada' then ahora else b.entrada_en end,
    entrada_por  = case when p_tipo = 'entrada' then p_por else b.entrada_por end,
    salida_en    = case when p_tipo = 'salida'  then ahora else b.salida_en end,
    salida_por   = case when p_tipo = 'salida'  then p_por else b.salida_por end
  returning * into fila;

  insert into public.llg_movimientos (package_uuid, orden, tipo, fecha, escaneado_por, codigo_leido, reemplazo)
  values (p_uuid, p_orden, p_tipo, ahora, p_por, p_codigo, previo is not null);

  return fila;
end $$;
grant execute on function public.llg_marcar(text,text,text,text,text,text,text,text,integer,text) to anon;


-- ---------- PARTE 2: CIERRE (correr DESPUES de que Claude publique la pagina nueva) ----------
-- Quita la version sin clave y la escritura directa con la llave publica.
-- Descomenta y corre estas lineas:
--
-- drop function if exists public.llg_marcar(text,text,text,text,text,text,text,text,integer);
-- revoke insert, update on public.llg_burritos    from anon;
-- revoke insert         on public.llg_movimientos from anon;
-- drop policy if exists "llg_insert"     on public.llg_burritos;
-- drop policy if exists "llg_update"     on public.llg_burritos;
-- drop policy if exists "llg_mov_insert" on public.llg_movimientos;
--
-- Verificar: anon solo debe tener select en llg_*
-- select grantee, table_name, string_agg(privilege_type, ', ' order by privilege_type) as permisos
-- from information_schema.role_table_grants
-- where table_schema = 'public' and table_name in ('llg_burritos','llg_movimientos') and grantee = 'anon'
-- group by grantee, table_name;
