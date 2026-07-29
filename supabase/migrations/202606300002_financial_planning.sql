-- Conciliación, nómina, presupuesto y evidencias.
create table public.bank_movements (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts(id),
  bank_date date not null, description text not null, reference text,
  amount numeric(12,2) not null check (amount <> 0),
  income_id uuid references public.incomes(id),
  status public.reconciliation_status not null default 'pendiente',
  imported_by uuid not null references public.profiles(id),
  imported_at timestamptz not null default now()
);
create unique index bank_movement_dedup on public.bank_movements
  (account_id,bank_date,amount,coalesce(reference,''),description);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  employee_number text not null unique, full_name text not null,
  position text, base_pay numeric(12,2) not null default 0,
  active boolean not null default true
);
create table public.payroll_periods (
  id uuid primary key default gen_random_uuid(),
  starts_on date not null, ends_on date not null,
  account_id uuid references public.accounts(id),
  status public.movement_status not null default 'borrador',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(starts_on,ends_on), check(ends_on>=starts_on)
);
create table public.payroll_items (
  id uuid primary key default gen_random_uuid(),
  payroll_period_id uuid not null references public.payroll_periods(id) on delete cascade,
  employee_id uuid not null references public.employees(id),
  earnings numeric(12,2) not null default 0,
  loan_deduction numeric(12,2) not null default 0,
  other_deductions numeric(12,2) not null default 0, incidents text,
  net_pay numeric(12,2) generated always as
    (earnings-loan_deduction-other_deductions) stored,
  unique(payroll_period_id,employee_id)
);

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references public.school_cycles(id),
  name text not null, status public.movement_status not null default 'borrador',
  assumptions jsonb not null default '{}',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(), unique(cycle_id,name)
);
create table public.budget_lines (
  id uuid primary key default gen_random_uuid(),
  budget_id uuid not null references public.budgets(id) on delete cascade,
  cycle_month_id uuid not null references public.cycle_months(id),
  direction text not null check(direction in ('ingreso','egreso')),
  concept_id uuid references public.payment_concepts(id),
  expense_category_id uuid references public.expense_categories(id),
  projected_enrollment integer, unit_amount numeric(12,2),
  amount numeric(14,2) not null check(amount>=0),
  check((direction='ingreso' and concept_id is not null and expense_category_id is null)
    or (direction='egreso' and expense_category_id is not null and concept_id is null))
);
create table public.pre_enrollments (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references public.school_cycles(id),
  prospective_name text not null, level text not null, grade text not null,
  expected_fee numeric(12,2), probability numeric(5,2) default 100
    check(probability between 0 and 100), status text not null default 'preinscrito'
);
create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  bucket text not null, object_path text not null unique,
  entity_type text not null, entity_id uuid not null, file_name text not null,
  mime_type text, uploaded_by uuid not null references public.profiles(id),
  uploaded_at timestamptz not null default now()
);

create view public.budget_vs_actual with (security_invoker=true) as
select b.id budget_id,cm.id cycle_month_id,cm.number,cm.name month_name,
  coalesce(sum(bl.amount) filter(where bl.direction='ingreso'),0) budget_income,
  coalesce((select sum(i.amount) from incomes i where i.status='confirmado'
    and extract(month from i.paid_on)=extract(month from cm.starts_on)),0) actual_income,
  coalesce(sum(bl.amount) filter(where bl.direction='egreso'),0) budget_expense,
  coalesce((select sum(e.total) from expenses e where e.status='confirmado'
    and extract(month from e.spent_on)=extract(month from cm.starts_on)),0) actual_expense
from budgets b join cycle_months cm on cm.cycle_id=b.cycle_id
left join budget_lines bl on bl.budget_id=b.id and bl.cycle_month_id=cm.id
group by b.id,cm.id,cm.number,cm.name,cm.starts_on;

create view public.cash_flow with (security_invoker=true) as
select d::date movement_date,
  coalesce((select sum(amount) from incomes where paid_on=d and status='confirmado'),0) incomes,
  coalesce((select sum(total) from expenses where spent_on=d and status='confirmado'),0) expenses,
  coalesce((select sum(amount) from transfers where transferred_on=d and status='confirmado'),0) internal_transfers
from generate_series(current_date-interval '1 year',current_date,interval '1 day') d;

alter table public.bank_movements enable row level security;
alter table public.employees enable row level security;
alter table public.payroll_periods enable row level security;
alter table public.payroll_items enable row level security;
alter table public.budgets enable row level security;
alter table public.budget_lines enable row level security;
alter table public.pre_enrollments enable row level security;
alter table public.attachments enable row level security;
do $$ declare t text; begin
  foreach t in array array['bank_movements','employees','payroll_periods',
    'payroll_items','budgets','budget_lines','pre_enrollments','attachments']
  loop
    execute format('create policy staff_read on public.%I for select to authenticated using (public.is_active_staff())',t);
    execute format('create policy staff_write on public.%I for all to authenticated using (public.is_active_staff()) with check (public.is_active_staff())',t);
  end loop;
end $$;
