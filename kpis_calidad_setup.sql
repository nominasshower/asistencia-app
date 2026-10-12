-- KPIs Calidad: captura de lo que ConnectIT/Odoo no tienen (quejas de clientes y retrabajo en línea).
-- Pegar completo en Supabase > SQL Editor > Run. Se puede correr más de una vez.

create table if not exists public.calidad_quejas (
  id           bigint generated always as identity primary key,
  fecha        date        not null,
  cliente      text        not null,
  tipo         text        not null default 'Queja' check (tipo in ('Queja','Reclamación')),
  orden        text,                         -- PO / orden / cotización
  modelo       text,
  descripcion  text,
  area         text,                         -- área responsable (Vaciado, Pintura, Acabado, Empaque, Embarque, Transporte, Otro)
  estatus      text        not null default 'Abierta' check (estatus in ('Abierta','En proceso','Cerrada')),
  capturado_por text,
  created_at   timestamptz not null default now()
);
create index if not exists calidad_quejas_fecha_idx on public.calidad_quejas (fecha);

create table if not exists public.calidad_retrabajo_linea (
  id           bigint generated always as identity primary key,
  fecha        date        not null,
  linea        text        not null default 'L1',
  tipo         text        not null check (tipo in ('Menor','Mayor')),
  cantidad     integer     not null check (cantidad > 0),
  defecto      text,
  sku          text,
  capturado_por text,
  created_at   timestamptz not null default now()
);
create index if not exists calidad_retrabajo_linea_fecha_idx on public.calidad_retrabajo_linea (fecha);

-- Acceso con la llave pública (igual que el resto de las páginas de esta app)
alter table public.calidad_quejas          enable row level security;
alter table public.calidad_retrabajo_linea enable row level security;

do $$
declare t text;
begin
  foreach t in array array['calidad_quejas','calidad_retrabajo_linea'] loop
    execute format('drop policy if exists %I on public.%I', t||'_select', t);
    execute format('drop policy if exists %I on public.%I', t||'_insert', t);
    execute format('drop policy if exists %I on public.%I', t||'_update', t);
    execute format('drop policy if exists %I on public.%I', t||'_delete', t);
    execute format('create policy %I on public.%I for select to anon using (true)', t||'_select', t);
    execute format('create policy %I on public.%I for insert to anon with check (true)', t||'_insert', t);
    execute format('create policy %I on public.%I for update to anon using (true) with check (true)', t||'_update', t);
    execute format('create policy %I on public.%I for delete to anon using (true)', t||'_delete', t);
  end loop;
end $$;

grant select, insert, update, delete on public.calidad_quejas          to anon;
grant select, insert, update, delete on public.calidad_retrabajo_linea to anon;
grant usage, select on all sequences in schema public to anon;
