-- ============================================================
-- LLG: la fecha de llegada/salida la pone Supabase (now()), no el dispositivo.
-- La pagina llama POST /rest/v1/rpc/llg_marcar; guarda estado + bitacora en
-- una sola transaccion (o se guardan los dos o ninguno).
-- Ejecutar en Supabase > SQL Editor despues de supabase_llg_bodega.sql.
-- ============================================================
create or replace function public.llg_marcar(
  p_uuid text, p_tipo text, p_por text, p_codigo text,
  p_orden text, p_cliente text, p_po text, p_tipo_paquete text, p_piezas integer
) returns public.llg_burritos
language plpgsql
security invoker
as $$
declare
  ahora timestamptz := now();
  previo timestamptz;
  fila public.llg_burritos;
begin
  if p_tipo not in ('entrada','salida') then
    raise exception 'tipo invalido: %', p_tipo;
  end if;
  if p_uuid !~ '^[0-9a-f]{12}$' then
    raise exception 'uuid invalido: %', p_uuid;
  end if;

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

grant execute on function public.llg_marcar(text,text,text,text,text,text,text,text,integer) to anon;
