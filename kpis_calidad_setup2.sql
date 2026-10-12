-- KPIs Calidad (parte 2): donde el servidor (n8n en ares) deja los datos de ConnectIT para que la pagina los lea.
-- Pegar completo en Supabase > SQL Editor > Run. Se puede correr mas de una vez.

create table if not exists public.calidad_kpis_data (
  id        text primary key,            -- 'principal'
  datos     jsonb       not null,
  generado  timestamptz not null default now()
);

alter table public.calidad_kpis_data enable row level security;
drop policy if exists calidad_kpis_data_select on public.calidad_kpis_data;
drop policy if exists calidad_kpis_data_insert on public.calidad_kpis_data;
drop policy if exists calidad_kpis_data_update on public.calidad_kpis_data;
create policy calidad_kpis_data_select on public.calidad_kpis_data for select to anon using (true);
create policy calidad_kpis_data_insert on public.calidad_kpis_data for insert to anon with check (true);
create policy calidad_kpis_data_update on public.calidad_kpis_data for update to anon using (true) with check (true);
grant select, insert, update on public.calidad_kpis_data to anon;
