-- Base operativa para iniciar el ciclo actual y retirar demostraciones sin borrar historial.

alter table public.students
  add column if not exists data_origin text not null default 'operativo'
  check (data_origin in ('operativo', 'demo'));

alter table public.expenses
  add column if not exists data_origin text not null default 'operativo'
  check (data_origin in ('operativo', 'demo'));

-- El ciclo se mantiene con septiembre como mes 1, como se opera en el colegio.
insert into public.school_cycles (name, starts_on, ends_on, active)
values ('2026–2027', '2026-09-01', '2027-08-31', true)
on conflict (name) do update set
  starts_on = excluded.starts_on,
  ends_on = excluded.ends_on,
  active = true;

update public.school_cycles
set active = (name = '2026–2027');

update public.students
set active = false
where cycle_id not in (select id from public.school_cycles where active);

with active_cycle as (
  select id from public.school_cycles where name = '2026–2027'
), month_data(number, name, starts_on, ends_on) as (
  values
    (1::smallint, 'Septiembre', '2026-09-01'::date, '2026-09-30'::date),
    (2::smallint, 'Octubre', '2026-10-01'::date, '2026-10-31'::date),
    (3::smallint, 'Noviembre', '2026-11-01'::date, '2026-11-30'::date),
    (4::smallint, 'Diciembre', '2026-12-01'::date, '2026-12-31'::date),
    (5::smallint, 'Enero', '2027-01-01'::date, '2027-01-31'::date),
    (6::smallint, 'Febrero', '2027-02-01'::date, '2027-02-28'::date),
    (7::smallint, 'Marzo', '2027-03-01'::date, '2027-03-31'::date),
    (8::smallint, 'Abril', '2027-04-01'::date, '2027-04-30'::date),
    (9::smallint, 'Mayo', '2027-05-01'::date, '2027-05-31'::date),
    (10::smallint, 'Junio', '2027-06-01'::date, '2027-06-30'::date),
    (11::smallint, 'Julio', '2027-07-01'::date, '2027-07-31'::date),
    (12::smallint, 'Agosto', '2027-08-01'::date, '2027-08-31'::date)
)
insert into public.cycle_months (cycle_id, number, name, starts_on, ends_on)
select active_cycle.id, month_data.number, month_data.name, month_data.starts_on, month_data.ends_on
from active_cycle cross join month_data
on conflict (cycle_id, number) do update set
  name = excluded.name,
  starts_on = excluded.starts_on,
  ends_on = excluded.ends_on;

-- Marca las filas creadas por la demostración original. Las filas operativas nuevas
-- no se incluyen aunque reutilicen una matrícula después.
update public.students
set data_origin = 'demo'
where enrollment in ('CEI-0301','CEI-0302','CEI-0303','CEI-0304','CEI-0305',
                     'CEI-0306','CEI-0307','CEI-0308','CEI-0309','CEI-0310')
  and first_name in ('Sofía','Sofia','Mauricio','Ana Paula','Valentina','José','Jose',
                     'Mariana','Emiliano','Camila','Leonardo','Regina');

update public.expenses
set data_origin = 'demo'
where description like 'Prueba financiera -%';

create or replace function public.import_student_finances(p_rows jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_item jsonb;
  v_cycle_id uuid;
  v_cycle_month_id uuid;
  v_student_id uuid;
  v_contact_id uuid;
  v_concept_id uuid;
  v_charge_id uuid;
  v_account_id uuid;
  v_amount numeric(12,2);
  v_total numeric(12,2);
  v_late_rate numeric(5,2);
  v_late_fee numeric(12,2);
  v_paid_amount numeric(12,2);
  v_due_on date;
  v_paid_on date;
  v_method text;
  v_students integer := 0;
  v_payments integer := 0;
  v_late_fees numeric(12,2) := 0;
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'No hay filas para importar'; end if;
  if jsonb_array_length(p_rows) > 500 then raise exception 'El limite es de 500 alumnos por archivo'; end if;

  select id into v_cycle_id from public.school_cycles where active order by starts_on desc limit 1;
  if v_cycle_id is null then raise exception 'No hay un ciclo escolar activo'; end if;

  for v_item in select * from jsonb_array_elements(p_rows) loop
    if nullif(trim(v_item ->> 'enrollment'), '') is null
      or nullif(trim(v_item ->> 'first_name'), '') is null
      or nullif(trim(v_item ->> 'grade'), '') is null then
      raise exception 'Cada fila requiere matricula, nombre y grado';
    end if;

    insert into public.students (enrollment, first_name, last_name, level, grade, cycle_id, active, data_origin)
    values (
      trim(v_item ->> 'enrollment'),
      trim(v_item ->> 'first_name'),
      coalesce(nullif(trim(v_item ->> 'last_name'), ''), 'Pendiente'),
      coalesce(nullif(trim(v_item ->> 'level'), ''), 'Primaria'),
      trim(v_item ->> 'grade'), v_cycle_id, true, 'operativo'
    )
    on conflict (enrollment, cycle_id) do update set
      first_name = excluded.first_name,
      last_name = excluded.last_name,
      level = excluded.level,
      grade = excluded.grade,
      active = true,
      data_origin = 'operativo',
      updated_at = now()
    returning id into v_student_id;
    v_students := v_students + 1;

    if nullif(trim(v_item ->> 'tutor_name'), '') is not null then
      select id into v_contact_id from public.student_contacts
      where student_id = v_student_id and primary_contact order by id limit 1;
      if v_contact_id is null then
        insert into public.student_contacts (student_id, full_name, relationship, phone, email, primary_contact)
        values (v_student_id, trim(v_item ->> 'tutor_name'), 'Tutor',
          nullif(trim(v_item ->> 'tutor_phone'), ''), nullif(trim(v_item ->> 'tutor_email'), ''), true);
      else
        update public.student_contacts set
          full_name = trim(v_item ->> 'tutor_name'),
          phone = nullif(trim(v_item ->> 'tutor_phone'), ''),
          email = nullif(trim(v_item ->> 'tutor_email'), '')
        where id = v_contact_id;
      end if;
    end if;

    v_amount := coalesce(nullif(v_item ->> 'amount', '')::numeric, 0);
    v_due_on := nullif(v_item ->> 'due_on', '')::date;
    v_paid_on := nullif(v_item ->> 'paid_on', '')::date;
    v_method := coalesce(nullif(v_item ->> 'payment_method', ''), 'efectivo');
    v_late_rate := coalesce(nullif(v_item ->> 'late_fee_rate', '')::numeric, 10);
    if v_late_rate < 0 or v_late_rate > 100 then raise exception 'El recargo debe estar entre 0 y 100'; end if;
    v_late_fee := case when v_paid_on is not null and v_due_on is not null and v_paid_on > v_due_on
      then round(v_amount * v_late_rate / 100, 2) else 0 end;
    v_total := v_amount + v_late_fee;

    if v_amount > 0 then
      select id into v_concept_id from public.payment_concepts
      where lower(unaccent(name)) = lower(unaccent(coalesce(nullif(v_item ->> 'concept', ''), 'Colegiatura')))
        and active limit 1;
      if v_concept_id is null then raise exception 'El concepto % no existe', v_item ->> 'concept'; end if;

      select id into v_cycle_month_id from public.cycle_months
      where cycle_id = v_cycle_id and v_due_on between starts_on and ends_on limit 1;

      insert into public.charges (student_id, cycle_id, cycle_month_id, concept_id, gross_amount, late_fee_amount, due_on)
      values (v_student_id, v_cycle_id, v_cycle_month_id, v_concept_id, v_total, v_late_fee, v_due_on)
      on conflict (student_id, cycle_id, cycle_month_id, concept_id) do update set
        gross_amount = greatest(public.charges.paid_amount, excluded.gross_amount),
        late_fee_amount = case when public.charges.paid_amount = 0 then excluded.late_fee_amount else public.charges.late_fee_amount end,
        due_on = excluded.due_on
      returning id, paid_amount into v_charge_id, v_paid_amount;

      if v_paid_on is not null and v_paid_amount < v_total then
        select id into v_account_id from public.accounts
        where active and kind = case when v_method = 'efectivo' then 'efectivo' else 'banco' end
        order by name limit 1;
        if v_account_id is null then raise exception 'No hay una cuenta financiera activa'; end if;
        perform public.register_student_payment(
          v_student_id, v_account_id, v_method,
          case when v_late_fee > 0 then 'Importado con recargo por atraso' else 'Importado desde lista de alumnos' end,
          v_paid_on, jsonb_build_array(jsonb_build_object('charge_id', v_charge_id, 'amount', v_total - v_paid_amount))
        );
        v_payments := v_payments + 1;
        v_late_fees := v_late_fees + v_late_fee;
      end if;
    end if;
  end loop;
  return jsonb_build_object('students', v_students, 'payments', v_payments, 'late_fees', v_late_fees);
end;
$$;

-- Permite cobrar todo o sólo una parte del saldo de un cargo.
drop function if exists public.create_student_charge(uuid, text, text, text, text, text, text, text, uuid, date, date, numeric, numeric, text);

create or replace function public.create_student_charge(
  p_student_id uuid, p_enrollment text, p_first_name text, p_last_name text,
  p_level text, p_grade text, p_tutor_name text, p_tutor_phone text,
  p_concept_id uuid, p_due_on date, p_paid_on date, p_base_amount numeric,
  p_late_fee_rate numeric default 10, p_payment_method text default 'efectivo',
  p_payment_amount numeric default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_cycle_id uuid;
  v_cycle_month_id uuid;
  v_student_id uuid;
  v_charge public.charges%rowtype;
  v_base numeric(12,2);
  v_late_fee numeric(12,2) := 0;
  v_account_id uuid;
  v_receipt_id uuid;
  v_payment_amount numeric(12,2);
  v_remaining numeric(12,2);
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if p_due_on is null then raise exception 'La fecha de vencimiento es obligatoria'; end if;
  if p_late_fee_rate < 0 or p_late_fee_rate > 100 then raise exception 'El porcentaje de recargo debe estar entre 0 y 100'; end if;
  if p_payment_method not in ('efectivo','transferencia','tarjeta','otro') then raise exception 'Forma de pago no valida'; end if;

  select id into v_cycle_id from public.school_cycles where active order by starts_on desc limit 1;
  if v_cycle_id is null then raise exception 'No hay un ciclo escolar activo'; end if;
  select id into v_cycle_month_id from public.cycle_months
  where cycle_id = v_cycle_id and p_due_on between starts_on and ends_on limit 1;

  if p_student_id is null then
    if nullif(trim(p_enrollment), '') is null or nullif(trim(p_first_name), '') is null
      or nullif(trim(p_last_name), '') is null or nullif(trim(p_grade), '') is null then
      raise exception 'Completa matricula, nombre, apellidos y grado del alumno';
    end if;
    insert into public.students (enrollment, first_name, last_name, level, grade, cycle_id, data_origin)
    values (upper(trim(p_enrollment)), trim(p_first_name), trim(p_last_name),
      coalesce(nullif(trim(p_level), ''), 'Primaria'), trim(p_grade), v_cycle_id, 'operativo')
    returning id into v_student_id;
    if nullif(trim(p_tutor_name), '') is not null then
      insert into public.student_contacts (student_id, full_name, relationship, phone, primary_contact)
      values (v_student_id, trim(p_tutor_name), 'Tutor', nullif(trim(p_tutor_phone), ''), true);
    end if;
  else
    select id into v_student_id from public.students
    where id = p_student_id and cycle_id = v_cycle_id and active;
    if v_student_id is null then raise exception 'El alumno seleccionado no esta activo'; end if;
  end if;

  select coalesce(
    (select amount from public.fees where cycle_id = v_cycle_id and concept_id = p_concept_id
      and level = (select level from public.students where id = v_student_id)
      and grade = (select grade from public.students where id = v_student_id) limit 1),
    (select nullif(base_amount, 0) from public.payment_concepts where id = p_concept_id and active),
    nullif(p_base_amount, 0)
  ) into v_base;
  if v_base is null or v_base <= 0 then raise exception 'El concepto no tiene una tarifa valida'; end if;
  if p_paid_on is not null and p_paid_on > p_due_on then v_late_fee := round(v_base * p_late_fee_rate / 100, 2); end if;

  select * into v_charge from public.charges
  where student_id = v_student_id and cycle_id = v_cycle_id and concept_id = p_concept_id
    and cycle_month_id is not distinct from v_cycle_month_id
    and status in ('pendiente','parcial','vencido')
  order by created_at desc limit 1 for update;

  if v_charge.id is null then
    if exists (select 1 from public.charges where student_id = v_student_id and cycle_id = v_cycle_id
      and concept_id = p_concept_id and cycle_month_id is not distinct from v_cycle_month_id and status = 'pagado') then
      raise exception 'Este concepto ya esta pagado para el periodo seleccionado';
    end if;
    insert into public.charges (student_id, cycle_id, cycle_month_id, concept_id, gross_amount, late_fee_amount, due_on, status)
    values (v_student_id, v_cycle_id, v_cycle_month_id, p_concept_id, v_base + v_late_fee, v_late_fee, p_due_on,
      case when p_paid_on is null and p_due_on < current_date then 'vencido'::public.charge_status else 'pendiente'::public.charge_status end)
    returning * into v_charge;
  elsif v_charge.paid_amount = 0 then
    update public.charges set gross_amount = v_base + v_late_fee, late_fee_amount = v_late_fee,
      due_on = p_due_on, cycle_month_id = v_cycle_month_id,
      status = case when p_paid_on is null and p_due_on < current_date then 'vencido'::public.charge_status else 'pendiente'::public.charge_status end
    where id = v_charge.id returning * into v_charge;
  end if;

  v_remaining := v_charge.net_amount - v_charge.paid_amount;
  if p_paid_on is not null then
    v_payment_amount := coalesce(nullif(p_payment_amount, 0), v_remaining);
    if v_payment_amount <= 0 or v_payment_amount > v_remaining then
      raise exception 'El importe recibido debe ser mayor a cero y no superar el saldo de %', v_remaining;
    end if;
    select id into v_account_id from public.accounts
    where active and kind = case when p_payment_method = 'transferencia' then 'banco' else 'efectivo' end
    order by name limit 1;
    if v_account_id is null then raise exception 'No hay una cuenta financiera compatible'; end if;
    select public.register_student_payment(v_student_id, v_account_id, p_payment_method,
      case when v_late_fee > 0 then 'Pago con recargo por atraso' else 'Cobro registrado' end,
      p_paid_on, jsonb_build_array(jsonb_build_object('charge_id', v_charge.id, 'amount', v_payment_amount)))
    into v_receipt_id;
  else
    v_payment_amount := 0;
  end if;

  return jsonb_build_object(
    'student_id', v_student_id, 'charge_id', v_charge.id, 'receipt_id', v_receipt_id,
    'base_amount', v_base, 'late_fee_amount', v_late_fee,
    'total', v_charge.net_amount, 'payment_amount', v_payment_amount,
    'payment_status', case
      when p_paid_on is null then 'no_pagado'
      when v_payment_amount < v_remaining then 'parcial'
      when p_paid_on > p_due_on then 'pagado_retraso'
      else 'pagado' end
  );
end;
$$;

create or replace function public.load_financial_demo()
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_result jsonb;
  v_account_id uuid;
  v_category_id uuid;
  v_expenses integer := 0;
begin
  if not public.is_manager() then raise exception 'Solo Direccion puede cargar la prueba financiera'; end if;

  select public.import_student_finances(jsonb_build_array(
    jsonb_build_object('enrollment','CEI-0301','first_name','Sofia','last_name','Martinez Pech','level','Primaria','grade','4 Primaria','tutor_name','Laura Pech','concept','Colegiatura','amount',3250,'due_on','2026-06-10','paid_on','2026-06-08','payment_method','efectivo'),
    jsonb_build_object('enrollment','CEI-0302','first_name','Mauricio','last_name','Torres Solis','level','Primaria','grade','3 Primaria','tutor_name','Daniel Torres','concept','Colegiatura','amount',3250,'due_on','2026-06-10','paid_on','2026-06-10','payment_method','transferencia'),
    jsonb_build_object('enrollment','CEI-0303','first_name','Ana Paula','last_name','Diaz Cervera','level','Primaria','grade','2 Primaria','tutor_name','Monica Diaz','concept','Colegiatura','amount',3250,'due_on','2026-06-10','paid_on','2026-06-05','payment_method','tarjeta'),
    jsonb_build_object('enrollment','CEI-0304','first_name','Valentina','last_name','Lopez May','level','Primaria','grade','5 Primaria','tutor_name','Carlos Lopez','concept','Colegiatura','amount',3250,'due_on','2026-06-10','paid_on','2026-06-09','payment_method','efectivo'),
    jsonb_build_object('enrollment','CEI-0305','first_name','Jose','last_name','Pech Chan','level','Primaria','grade','1 Primaria','tutor_name','Maria Chan','concept','Colegiatura','amount',3250,'due_on','2026-06-10','paid_on','2026-06-14','payment_method','transferencia'),
    jsonb_build_object('enrollment','CEI-0306','first_name','Mariana','last_name','Solis Poot','level','Primaria','grade','6 Primaria','tutor_name','Arturo Solis','concept','Colegiatura','amount',3250,'due_on','2026-06-10','paid_on','2026-06-18','payment_method','efectivo'),
    jsonb_build_object('enrollment','CEI-0307','first_name','Emiliano','last_name','Mendez Ku','level','Primaria','grade','3 Primaria','tutor_name','Rebeca Ku','concept','Colegiatura','amount',3250,'due_on','2026-06-10','paid_on','2026-06-12','payment_method','transferencia'),
    jsonb_build_object('enrollment','CEI-0308','first_name','Camila','last_name','Gongora Pool','level','Primaria','grade','2 Primaria','tutor_name','Ivan Pool','concept','Colegiatura','amount',3250,'due_on','2026-06-10','payment_method','efectivo'),
    jsonb_build_object('enrollment','CEI-0309','first_name','Leonardo','last_name','Canto Uc','level','Primaria','grade','4 Primaria','tutor_name','Paola Canto','concept','Colegiatura','amount',3250,'due_on','2026-06-10','payment_method','efectivo'),
    jsonb_build_object('enrollment','CEI-0310','first_name','Regina','last_name','Sanchez Ek','level','Primaria','grade','1 Primaria','tutor_name','Fernando Ek','concept','Colegiatura','amount',3250,'due_on','2026-06-10','payment_method','efectivo')
  )) into v_result;

  update public.students set data_origin = 'demo'
  where enrollment in ('CEI-0301','CEI-0302','CEI-0303','CEI-0304','CEI-0305','CEI-0306','CEI-0307','CEI-0308','CEI-0309','CEI-0310');

  select id into v_account_id from public.accounts where active and kind = 'efectivo' order by name limit 1;
  select id into v_category_id from public.expense_categories where active order by name limit 1;
  if v_account_id is not null and v_category_id is not null then
    insert into public.expenses (account_id, category_id, spent_on, supplier, description, subtotal, payment_method, created_by, data_origin)
    select v_account_id, v_category_id, item.spent_on, item.supplier, item.description, item.subtotal, 'efectivo', auth.uid(), 'demo'
    from (values
      ('2026-06-03'::date, 'Papeleria Escolar', 'Prueba financiera - material para alumnos', 2460::numeric),
      ('2026-06-11'::date, 'JAPAY', 'Prueba financiera - servicio de agua', 1840::numeric),
      ('2026-06-20'::date, 'Mantenimiento CEI', 'Prueba financiera - mantenimiento', 3800::numeric)
    ) as item(spent_on, supplier, description, subtotal)
    where not exists (select 1 from public.expenses existing where existing.description = item.description);
    get diagnostics v_expenses = row_count;
  end if;
  return v_result || jsonb_build_object('expenses', v_expenses);
end;
$$;

create or replace function public.clear_financial_demo(p_confirmation text)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_students integer;
  v_charges integer;
  v_incomes integer;
  v_receipts integer;
  v_expenses integer;
begin
  if not public.is_manager() then raise exception 'Solo Direccion puede retirar la prueba financiera'; end if;
  if p_confirmation <> 'BORRAR_PRUEBA_CEI' then raise exception 'Confirmacion invalida'; end if;

  select count(*) into v_students from public.students where data_origin = 'demo' and active;
  select count(*) into v_charges from public.charges c join public.students s on s.id = c.student_id where s.data_origin = 'demo' and c.status <> 'cancelado';
  select count(*) into v_incomes from public.incomes i join public.students s on s.id = i.student_id where s.data_origin = 'demo' and i.status <> 'cancelado';
  select count(*) into v_receipts from public.receipts r join public.students s on s.id = r.student_id where s.data_origin = 'demo' and r.status <> 'cancelado';
  select count(*) into v_expenses from public.expenses where data_origin = 'demo' and status <> 'cancelado';

  update public.incomes i set status = 'cancelado' where i.student_id in (select id from public.students where data_origin = 'demo');
  update public.receipts r set status = 'cancelado', cancelled_by = auth.uid(), cancelled_at = now()
  where r.student_id in (select id from public.students where data_origin = 'demo');
  update public.charges c set status = 'cancelado' where c.student_id in (select id from public.students where data_origin = 'demo');
  update public.expenses set status = 'cancelado' where data_origin = 'demo';
  update public.students set active = false where data_origin = 'demo';

  return jsonb_build_object('students', v_students, 'charges', v_charges, 'incomes', v_incomes,
    'receipts', v_receipts, 'expenses', v_expenses);
end;
$$;

drop policy if exists staff_students_write on public.students;
create policy staff_students_insert on public.students for insert to authenticated
  with check (public.is_active_staff());
create policy staff_students_update on public.students for update to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());

drop policy if exists staff_contacts_write on public.student_contacts;
create policy staff_contacts_insert on public.student_contacts for insert to authenticated
  with check (public.is_active_staff());
create policy staff_contacts_update on public.student_contacts for update to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());

drop policy if exists staff_charges_write on public.charges;
create policy staff_charges_insert on public.charges for insert to authenticated
  with check (public.is_active_staff());
create policy staff_charges_update on public.charges for update to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());

grant execute on function public.create_student_charge(uuid, text, text, text, text, text, text, text, uuid, date, date, numeric, numeric, text, numeric) to authenticated;
grant execute on function public.clear_financial_demo(text) to authenticated;
