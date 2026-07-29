-- Centro Educativo Itzamná · núcleo financiero inicial
create extension if not exists unaccent;
create extension if not exists pgcrypto;

create type public.app_role as enum ('admin','direccion','caja','captura');
create type public.movement_status as enum ('borrador','confirmado','cancelado');
create type public.charge_status as enum ('pendiente','parcial','pagado','vencido','cancelado');
create type public.reconciliation_status as enum ('pendiente','conciliado','duplicado','no_identificado');
create type public.expense_type as enum ('costo','gasto','nomina');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role public.app_role not null default 'captura',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.school_cycles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  starts_on date not null,
  ends_on date not null,
  active boolean not null default false,
  check (ends_on > starts_on)
);

create table public.cycle_months (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references public.school_cycles(id) on delete cascade,
  number smallint not null check (number between 1 and 12),
  name text not null,
  starts_on date not null,
  ends_on date not null,
  unique (cycle_id, number)
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  enrollment text not null,
  first_name text not null,
  last_name text not null,
  level text not null,
  grade text not null,
  cycle_id uuid not null references public.school_cycles(id),
  active boolean not null default true,
  allergies text,
  notes text,
  search_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (enrollment, cycle_id)
);

create or replace function public.set_student_search_text()
returns trigger language plpgsql set search_path = public as $$
begin
  new.search_text := lower(unaccent(new.enrollment || ' ' || new.first_name || ' ' || new.last_name));
  return new;
end $$;

create trigger students_search_text_trigger
before insert or update of enrollment, first_name, last_name on public.students
for each row execute function public.set_student_search_text();

create index students_search_idx on public.students using gin (to_tsvector('simple', search_text));

create table public.student_contacts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  full_name text not null,
  relationship text not null,
  phone text,
  email text,
  primary_contact boolean not null default false
);

create table public.payment_concepts (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  classification text not null,
  periodicity text not null default 'unico',
  base_amount numeric(12,2) not null default 0 check (base_amount >= 0),
  active boolean not null default true
);

create table public.fees (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references public.school_cycles(id),
  concept_id uuid not null references public.payment_concepts(id),
  level text not null,
  grade text not null,
  amount numeric(12,2) not null check (amount >= 0),
  unique (cycle_id, concept_id, level, grade)
);

create table public.scholarships (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id),
  concept_id uuid references public.payment_concepts(id),
  kind text not null check (kind in ('interna','oficial')),
  percentage numeric(5,2) not null check (percentage between 0 and 100),
  starts_on date not null,
  ends_on date not null,
  active boolean not null default true,
  check (ends_on >= starts_on)
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  kind text not null check (kind in ('efectivo','banco')),
  opening_balance numeric(14,2) not null default 0,
  active boolean not null default true
);

create table public.charges (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id),
  cycle_id uuid not null references public.school_cycles(id),
  cycle_month_id uuid references public.cycle_months(id),
  concept_id uuid not null references public.payment_concepts(id),
  gross_amount numeric(12,2) not null check (gross_amount >= 0),
  discount_amount numeric(12,2) not null default 0 check (discount_amount >= 0),
  net_amount numeric(12,2) generated always as (gross_amount - discount_amount) stored,
  paid_amount numeric(12,2) not null default 0 check (paid_amount >= 0),
  due_on date,
  status public.charge_status not null default 'pendiente',
  created_at timestamptz not null default now(),
  check (discount_amount <= gross_amount),
  check (paid_amount <= gross_amount - discount_amount),
  unique nulls not distinct (student_id, cycle_id, cycle_month_id, concept_id)
);

create sequence public.receipt_folio_seq start 1;
create table public.receipts (
  id uuid primary key default gen_random_uuid(),
  folio text not null unique default ('REC-' || lpad(nextval('public.receipt_folio_seq')::text, 6, '0')),
  student_id uuid not null references public.students(id),
  account_id uuid not null references public.accounts(id),
  payment_method text not null check (payment_method in ('efectivo','transferencia','tarjeta','otro')),
  total numeric(12,2) not null check (total > 0),
  status public.movement_status not null default 'confirmado',
  notes text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  cancelled_by uuid references public.profiles(id),
  cancelled_at timestamptz
);

create table public.incomes (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid unique references public.receipts(id),
  student_id uuid references public.students(id),
  account_id uuid not null references public.accounts(id),
  paid_on date not null default current_date,
  amount numeric(12,2) not null check (amount > 0),
  payment_method text not null,
  bank_reference text,
  reconciliation_status public.reconciliation_status not null default 'pendiente',
  status public.movement_status not null default 'confirmado',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  income_id uuid not null references public.incomes(id),
  charge_id uuid not null references public.charges(id),
  amount numeric(12,2) not null check (amount > 0),
  unique (income_id, charge_id)
);

create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  type public.expense_type not null,
  active boolean not null default true
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts(id),
  category_id uuid not null references public.expense_categories(id),
  spent_on date not null,
  supplier text,
  description text not null,
  subtotal numeric(12,2) not null check (subtotal >= 0),
  tax numeric(12,2) not null default 0 check (tax >= 0),
  total numeric(12,2) generated always as (subtotal + tax) stored,
  payment_method text not null,
  status public.movement_status not null default 'confirmado',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.transfers (
  id uuid primary key default gen_random_uuid(),
  source_account_id uuid not null references public.accounts(id),
  destination_account_id uuid not null references public.accounts(id),
  transferred_on date not null,
  amount numeric(12,2) not null check (amount > 0),
  reason text not null,
  status public.movement_status not null default 'confirmado',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check (source_account_id <> destination_account_id)
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  table_name text not null,
  record_id uuid,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  performed_by uuid references public.profiles(id),
  performed_at timestamptz not null default now()
);

-- Confirma recibo, ingreso y aplicaciones en la misma transacción.
create or replace function public.register_cash_payment(
  p_student_id uuid, p_account_id uuid, p_method text, p_notes text,
  p_allocations jsonb
) returns uuid language plpgsql security invoker set search_path = public as $$
declare
  v_receipt_id uuid; v_income_id uuid; v_total numeric(12,2); v_item jsonb;
  v_charge public.charges%rowtype; v_amount numeric(12,2);
begin
  select coalesce(sum((x->>'amount')::numeric),0) into v_total
  from jsonb_array_elements(p_allocations) x;
  if v_total <= 0 then raise exception 'El total debe ser mayor a cero'; end if;

  insert into receipts(student_id,account_id,payment_method,total,notes,created_by)
  values(p_student_id,p_account_id,p_method,v_total,p_notes,auth.uid())
  returning id into v_receipt_id;
  insert into incomes(receipt_id,student_id,account_id,amount,payment_method,
    reconciliation_status,created_by)
  values(v_receipt_id,p_student_id,p_account_id,v_total,p_method,
    case when p_method='efectivo' then 'conciliado' else 'pendiente' end,auth.uid())
  returning id into v_income_id;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_amount := (v_item->>'amount')::numeric;
    select * into v_charge from charges where id=(v_item->>'charge_id')::uuid for update;
    if v_charge.student_id<>p_student_id or v_amount<=0
      or v_charge.paid_amount+v_amount>v_charge.net_amount then
      raise exception 'Aplicación inválida para el cargo';
    end if;
    insert into payment_allocations(income_id,charge_id,amount)
    values(v_income_id,v_charge.id,v_amount);
    update charges set paid_amount=paid_amount+v_amount,
      status=case when paid_amount+v_amount=net_amount then 'pagado'::charge_status
                  else 'parcial'::charge_status end where id=v_charge.id;
  end loop;
  return v_receipt_id;
end $$;

create view public.account_balances with (security_invoker=true) as
select a.id,a.name,a.kind,a.opening_balance
  + coalesce((select sum(i.amount) from incomes i where i.account_id=a.id and i.status='confirmado'),0)
  - coalesce((select sum(e.total) from expenses e where e.account_id=a.id and e.status='confirmado'),0)
  + coalesce((select sum(t.amount) from transfers t where t.destination_account_id=a.id and t.status='confirmado'),0)
  - coalesce((select sum(t.amount) from transfers t where t.source_account_id=a.id and t.status='confirmado'),0)
  as balance
from accounts a where a.active;

alter table public.profiles enable row level security;
alter table public.school_cycles enable row level security;
alter table public.cycle_months enable row level security;
alter table public.students enable row level security;
alter table public.student_contacts enable row level security;
alter table public.payment_concepts enable row level security;
alter table public.fees enable row level security;
alter table public.scholarships enable row level security;
alter table public.accounts enable row level security;
alter table public.charges enable row level security;
alter table public.receipts enable row level security;
alter table public.incomes enable row level security;
alter table public.payment_allocations enable row level security;
alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.transfers enable row level security;
alter table public.audit_log enable row level security;

create or replace function public.is_active_staff() returns boolean
language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and active) $$;
create or replace function public.is_manager() returns boolean
language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and active and role in ('admin','direccion')) $$;

-- Lectura para personal autenticado. Escritura operativa; catálogos sólo dirección/admin.
do $$
declare t text;
begin
  foreach t in array array['profiles','school_cycles','cycle_months','students',
    'student_contacts','payment_concepts','fees','scholarships','accounts','charges',
    'receipts','incomes','payment_allocations','expense_categories','expenses',
    'transfers','audit_log']
  loop execute format('create policy staff_read on public.%I for select to authenticated using (public.is_active_staff())',t);
  end loop;
end $$;
create policy staff_students_write on public.students for all to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());
create policy staff_contacts_write on public.student_contacts for all to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());
create policy staff_charges_write on public.charges for all to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());
create policy staff_receipts_write on public.receipts for insert to authenticated
  with check (public.is_active_staff() and created_by=auth.uid());
create policy staff_incomes_write on public.incomes for insert to authenticated
  with check (public.is_active_staff() and created_by=auth.uid());
create policy staff_allocations_write on public.payment_allocations for insert to authenticated
  with check (public.is_active_staff());
create policy staff_expenses_write on public.expenses for insert to authenticated
  with check (public.is_active_staff() and created_by=auth.uid());
create policy staff_transfers_write on public.transfers for insert to authenticated
  with check (public.is_active_staff() and created_by=auth.uid());
