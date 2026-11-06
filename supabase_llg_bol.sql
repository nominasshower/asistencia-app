-- LLG bodega Laredo: documento firmado (Signed BOL) por Q
-- Correr UNA vez en Supabase > SQL Editor. Solo crea una tabla nueva y 2 funciones; no toca nada existente.
-- Las fotos usan el mismo bucket 'llg-fotos' (carpeta bol/) y la misma politica de subida con clave.
-- A diferencia de las fotos de burritos, las del BOL NO se borran solas a los 90 dias (es un documento firmado).

-- 1) Tabla: una fila por foto subida (una Q puede tener varias hojas)
create table if not exists public.llg_bol (
  id          bigint generated always as identity primary key,
  q           text        not null,
  foto_url    text        not null,
  subido_por  text        not null,
  subido_en   timestamptz not null default now()
);
create index if not exists llg_bol_q_idx on public.llg_bol (q);

-- Sin acceso directo desde la llave publica: solo por las funciones de abajo (que piden la clave)
alter table public.llg_bol enable row level security;
revoke all on public.llg_bol from anon, authenticated;

-- 2) Subir un BOL (solo con la clave de la bodega). La hora la pone el servidor.
create or replace function public.llg_subir_bol(p_q text, p_por text, p_foto text, p_clave text)
returns public.llg_bol
language plpgsql security definer set search_path = public as $$
declare
  q_ok text := upper(btrim(p_q));
  fila public.llg_bol;
begin
  if not public.llg_clave_ok(p_clave) then
    raise exception 'clave_invalida' using errcode = '28000';
  end if;
  if q_ok !~ '^Q[0-9]{4,6}$' then raise exception 'q invalida: %', p_q; end if;
  if coalesce(btrim(p_por), '') = '' then raise exception 'falta nombre'; end if;
  if p_foto not like 'https://xzwlbrirzfogbqhywtvj.supabase.co/storage/v1/object/public/llg-fotos/bol/%' then
    raise exception 'foto invalida';
  end if;
  insert into public.llg_bol (q, foto_url, subido_por) values (q_ok, p_foto, btrim(p_por))
  returning * into fila;
  return fila;
end $$;
grant execute on function public.llg_subir_bol(text, text, text, text) to anon;

-- 3) Ultimos BOL subidos (solo con la clave), para mostrarlos en la pagina
create or replace function public.llg_bol_recientes(p_clave text, p_limite integer default 10)
returns setof public.llg_bol
language sql security definer set search_path = public as $$
  select * from public.llg_bol
  where public.llg_clave_ok(p_clave)
  order by subido_en desc
  limit least(coalesce(p_limite, 10), 50);
$$;
grant execute on function public.llg_bol_recientes(text, integer) to anon;

-- 4) Verificar: ambas deben dar error 'clave_invalida' / 0 filas con una clave falsa
select * from public.llg_bol_recientes('x');   -- 0 filas
