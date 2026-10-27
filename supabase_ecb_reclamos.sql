-- ============================================================
-- EC Barton: reclamaciones (claims) con foto del lavabo, foto de su etiqueta y defectos.
-- Mismo esquema que LLG: la pagina del cliente exige una clave, las fotos van a Storage
-- y se borran solas a los 4 meses (120 dias). El registro del reclamo (texto) se conserva.
--
-- ORDEN:
--   1) Correr este archivo completo en el SQL Editor de Supabase.
--   2) Fijar las DOS claves (cliente e interna) con el bloque "CLAVES" de abajo.
--      Mientras no se fijen, ninguna clave es valida (no hay clave de ejemplo).
--   3) Claude publica las paginas (solo con tu visto bueno).
-- ============================================================

-- ---------- Claves (solo se guarda la huella, nunca la clave) ----------
create table if not exists public.ecb_config (
  id int primary key check (id = 1),
  clave_hash text,        -- clave que se le da a EC Barton (crear reclamos)
  admin_hash text         -- clave interna (ver reclamos, borrar fotos vencidas)
);
alter table public.ecb_config enable row level security;
revoke all on public.ecb_config from anon, authenticated;
insert into public.ecb_config (id) values (1) on conflict (id) do nothing;

create or replace function public.ecb_clave_ok(p_clave text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from public.ecb_config
                 where id = 1 and clave_hash is not null
                   and clave_hash = encode(sha256(convert_to(coalesce(p_clave,'') || 'ecb-reclamos', 'utf8')), 'hex'));
$$;
create or replace function public.ecb_admin_ok(p_clave text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from public.ecb_config
                 where id = 1 and admin_hash is not null
                   and admin_hash = encode(sha256(convert_to(coalesce(p_clave,'') || 'ecb-admin', 'utf8')), 'hex'));
$$;
revoke execute on function public.ecb_clave_ok(text), public.ecb_admin_ok(text) from anon, public;

create or replace function public.ecb_validar_clave(p_clave text) returns boolean
language sql security definer set search_path = public as $$ select public.ecb_clave_ok(p_clave); $$;
create or replace function public.ecb_validar_admin(p_clave text) returns boolean
language sql security definer set search_path = public as $$ select public.ecb_admin_ok(p_clave); $$;
grant execute on function public.ecb_validar_clave(text), public.ecb_validar_admin(text) to anon;

-- Claves en los encabezados (para Storage, que no recibe parametros)
create or replace function public.ecb_clave_header_ok() returns boolean
language sql security definer set search_path = public as $$
  select public.ecb_clave_ok(
    nullif(coalesce(current_setting('request.headers', true), '{}')::json ->> 'x-ecb-clave', ''));
$$;
create or replace function public.ecb_admin_header_ok() returns boolean
language sql security definer set search_path = public as $$
  select public.ecb_admin_ok(
    nullif(coalesce(current_setting('request.headers', true), '{}')::json ->> 'x-ecb-admin', ''));
$$;
grant execute on function public.ecb_clave_header_ok(), public.ecb_admin_header_ok() to anon;

-- ---------- Tabla de reclamos (nadie la lee ni escribe directo: todo por funciones con clave) ----------
create table if not exists public.ecb_reclamos (
  id bigint generated always as identity primary key,
  creado_en timestamptz not null default now(),
  orden text not null,                 -- numero de orden / PO que escribe el cliente
  nombre text not null,
  codigo_barras text,                  -- numero del codigo de barras de la etiqueta, escrito a mano por el cliente
  defectos text[] not null,
  comentario text,
  foto_lavabo_url text,
  foto_etiqueta_url text,
  fotos_borradas_en timestamptz        -- cuando se borraron las fotos (4 meses)
);
alter table public.ecb_reclamos enable row level security;
revoke all on public.ecb_reclamos from anon, authenticated;

-- ---------- Almacenamiento de fotos: solo JPEG, ~1.5 MB max ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ecb-reclamos', 'ecb-reclamos', true, 1500000, array['image/jpeg'])
on conflict (id) do update
  set public = true, file_size_limit = 1500000, allowed_mime_types = array['image/jpeg'];

drop policy if exists "ecb_fotos_insert" on storage.objects;
create policy "ecb_fotos_insert" on storage.objects for insert to anon
  with check (bucket_id = 'ecb-reclamos' and public.ecb_clave_header_ok());
-- Borrar exige TAMBIEN poder ver el objeto (si no, el DELETE responde 200 [] y no borra). Solo clave interna.
drop policy if exists "ecb_fotos_select" on storage.objects;
create policy "ecb_fotos_select" on storage.objects for select to anon
  using (bucket_id = 'ecb-reclamos' and public.ecb_admin_header_ok());
drop policy if exists "ecb_fotos_delete" on storage.objects;
create policy "ecb_fotos_delete" on storage.objects for delete to anon
  using (bucket_id = 'ecb-reclamos' and public.ecb_admin_header_ok());

-- ---------- Crear un reclamo (clave del cliente) ----------
alter table public.ecb_reclamos add column if not exists codigo_barras text;   -- para bases ya creadas
drop function if exists public.ecb_crear(text,text,text,text[],text,text,text);
create or replace function public.ecb_crear(
  p_clave text, p_orden text, p_nombre text,
  p_defectos text[], p_comentario text, p_foto_lavabo text, p_foto_etiqueta text,
  p_codigo text default null
) returns json
language plpgsql security definer set search_path = public as $$
declare
  pref constant text := 'https://xzwlbrirzfogbqhywtvj.supabase.co/storage/v1/object/public/ecb-reclamos/';
  fila public.ecb_reclamos;
begin
  if not public.ecb_clave_ok(p_clave) then
    raise exception 'clave_invalida' using errcode = '28000';
  end if;
  if length(btrim(coalesce(p_orden,''))) = 0 or length(p_orden) > 80 then raise exception 'orden invalida'; end if;
  if length(btrim(coalesce(p_nombre,''))) = 0 or length(p_nombre) > 120 then raise exception 'nombre invalido'; end if;
  if p_defectos is null or array_length(p_defectos, 1) is null or array_length(p_defectos, 1) > 20 then
    raise exception 'defectos invalidos';
  end if;
  if length(coalesce(p_comentario,'')) > 2000 or length(coalesce(p_codigo,'')) > 60 then raise exception 'texto muy largo'; end if;
  if p_foto_lavabo is null or p_foto_lavabo not like pref || '%'
     or p_foto_etiqueta is null or p_foto_etiqueta not like pref || '%' then
    raise exception 'fotos invalidas';
  end if;

  insert into public.ecb_reclamos (orden, nombre, codigo_barras, defectos, comentario, foto_lavabo_url, foto_etiqueta_url)
  values (btrim(p_orden), btrim(p_nombre), nullif(btrim(coalesce(p_codigo,'')), ''), p_defectos,
          nullif(btrim(coalesce(p_comentario,'')), ''), p_foto_lavabo, p_foto_etiqueta)
  returning * into fila;

  return json_build_object('id', fila.id, 'folio', 'ECB-' || lpad(fila.id::text, 5, '0'), 'creado_en', fila.creado_en);
end $$;
grant execute on function public.ecb_crear(text,text,text,text[],text,text,text,text) to anon;

-- ---------- Ver reclamos (clave interna) ----------
create or replace function public.ecb_listar(p_admin text, p_desde date default null, p_hasta date default null)
returns setof public.ecb_reclamos
language sql security definer set search_path = public as $$
  select * from public.ecb_reclamos
  where public.ecb_admin_ok(p_admin)
    and (p_desde is null or creado_en >= p_desde)
    and (p_hasta is null or creado_en < p_hasta + 1)
  order by creado_en desc
  limit 1000;
$$;
grant execute on function public.ecb_listar(text, date, date) to anon;

-- ---------- Fotos vencidas (4 meses = 120 dias) y marca de borrado (clave interna) ----------
create or replace function public.ecb_fotos_vencidas(p_admin text, p_dias integer default 120)
returns table (id bigint, foto_lavabo_url text, foto_etiqueta_url text)
language sql security definer set search_path = public as $$
  select r.id, r.foto_lavabo_url, r.foto_etiqueta_url
  from public.ecb_reclamos r
  where public.ecb_admin_ok(p_admin)
    and r.fotos_borradas_en is null
    and r.creado_en < now() - make_interval(days => p_dias)
  order by r.creado_en
  limit 500;
$$;
grant execute on function public.ecb_fotos_vencidas(text, integer) to anon;

create or replace function public.ecb_foto_borrada(p_admin text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.ecb_admin_ok(p_admin) then
    raise exception 'clave_invalida' using errcode = '28000';
  end if;
  update public.ecb_reclamos
     set foto_lavabo_url = null, foto_etiqueta_url = null, fotos_borradas_en = now()
   where id = p_id and fotos_borradas_en is null;
end $$;
grant execute on function public.ecb_foto_borrada(text, bigint) to anon;

-- ---------- CLAVES (correr DESPUES, cambiando CLIENTE y INTERNA; NO guardar las claves en el repo, es publico) ----------
-- update public.ecb_config set
--   clave_hash = encode(sha256(convert_to('CLAVE_CLIENTE' || 'ecb-reclamos','utf8')),'hex'),
--   admin_hash = encode(sha256(convert_to('CLAVE_INTERNA' || 'ecb-admin','utf8')),'hex')
-- where id = 1;

-- ---------- Verificar ----------
select id, public, file_size_limit, allowed_mime_types from storage.buckets where id = 'ecb-reclamos';
select public.ecb_validar_clave('x') as cliente_x, public.ecb_validar_admin('x') as interna_x;  -- ambos false
