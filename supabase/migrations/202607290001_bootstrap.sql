-- Datos mínimos para que la aplicación pueda iniciar operaciones.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    'captura'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

insert into public.school_cycles (name, starts_on, ends_on, active)
values ('2025–2026', '2025-08-01', '2026-07-31', true)
on conflict (name) do update set active = excluded.active;

insert into public.payment_concepts (name, classification, periodicity, base_amount)
values
  ('Colegiatura', 'colegiatura', 'mensual', 0),
  ('Inscripción', 'inscripcion', 'unico', 0),
  ('Estancia', 'servicio', 'mensual', 0)
on conflict (name) do nothing;

insert into public.accounts (name, kind, opening_balance)
values
  ('Caja administración', 'efectivo', 0),
  ('Banco principal', 'banco', 0)
on conflict (name) do nothing;

insert into public.expense_categories (name, type)
values
  ('Servicios', 'gasto'),
  ('Material escolar', 'costo'),
  ('Mantenimiento', 'gasto'),
  ('Nómina', 'nomina')
on conflict (name) do nothing;
