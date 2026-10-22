-- ============================================================
-- LLG: una foto por burrito, tomada al darle "Llego".
-- Orden: 1) correr este SQL  2) Claude publica la pagina con foto.
-- La pagina actual sigue funcionando mientras tanto.
-- ============================================================

-- 1) Donde se guarda el enlace de la foto (en el registro del burrito)
alter table public.llg_burritos add column if not exists foto_url text;

-- 2) Espacio de almacenamiento: solo JPEG, maximo ~1.5 MB por foto, lectura por enlace
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('llg-fotos', 'llg-fotos', true, 1500000, array['image/jpeg'])
on conflict (id) do update
  set public = true, file_size_limit = 1500000, allowed_mime_types = array['image/jpeg'];

-- 3) Subir una foto exige la clave de la bodega (viaja en el encabezado x-llg-clave)
create or replace function public.llg_clave_header_ok() returns boolean
language sql security definer set search_path = public as $$
  select public.llg_clave_ok(
    nullif(coalesce(current_setting('request.headers', true), '{}')::json ->> 'x-llg-clave', ''));
$$;
grant execute on function public.llg_clave_header_ok() to anon;

drop policy if exists "llg_fotos_insert" on storage.objects;
create policy "llg_fotos_insert" on storage.objects for insert to anon
  with check (bucket_id = 'llg-fotos' and public.llg_clave_header_ok());

-- 4) llg_marcar acepta la foto (opcional). Se reemplaza la version anterior.
drop function if exists public.llg_marcar(text,text,text,text,text,text,text,text,integer,text);

create or replace function public.llg_marcar(
  p_uuid text, p_tipo text, p_por text, p_codigo text,
  p_orden text, p_cliente text, p_po text, p_tipo_paquete text, p_piezas integer, p_clave text,
  p_foto text default null
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
  if p_foto is not null and p_foto not like 'https://xzwlbrirzfogbqhywtvj.supabase.co/storage/v1/object/public/llg-fotos/%' then
    raise exception 'foto invalida';
  end if;

  select case when p_tipo = 'entrada' then entrada_en else salida_en end
    into previo from public.llg_burritos where package_uuid = p_uuid;

  insert into public.llg_burritos as b
    (package_uuid, orden, cliente, po_cliente, tipo_paquete, piezas,
     entrada_en, entrada_por, salida_en, salida_por, foto_url)
  values
    (p_uuid, p_orden, p_cliente, p_po, p_tipo_paquete, p_piezas,
     case when p_tipo = 'entrada' then ahora end, case when p_tipo = 'entrada' then p_por end,
     case when p_tipo = 'salida'  then ahora end, case when p_tipo = 'salida'  then p_por end,
     p_foto)
  on conflict (package_uuid) do update set
    orden        = coalesce(excluded.orden, b.orden),
    cliente      = coalesce(excluded.cliente, b.cliente),
    po_cliente   = coalesce(excluded.po_cliente, b.po_cliente),
    tipo_paquete = coalesce(excluded.tipo_paquete, b.tipo_paquete),
    piezas       = coalesce(excluded.piezas, b.piezas),
    entrada_en   = case when p_tipo = 'entrada' then ahora else b.entrada_en end,
    entrada_por  = case when p_tipo = 'entrada' then p_por else b.entrada_por end,
    salida_en    = case when p_tipo = 'salida'  then ahora else b.salida_en end,
    salida_por   = case when p_tipo = 'salida'  then p_por else b.salida_por end,
    foto_url     = coalesce(excluded.foto_url, b.foto_url)
  returning * into fila;

  insert into public.llg_movimientos (package_uuid, orden, tipo, fecha, escaneado_por, codigo_leido, reemplazo)
  values (p_uuid, p_orden, p_tipo, ahora, p_por, p_codigo, previo is not null);

  return fila;
end $$;
grant execute on function public.llg_marcar(text,text,text,text,text,text,text,text,integer,text,text) to anon;

-- 5) Verificar: debe mostrar el bucket llg-fotos
select id, public, file_size_limit, allowed_mime_types from storage.buckets where id = 'llg-fotos';
