-- Importacion atomica, estados de pago y roles operativos.

update public.profiles set role = 'direccion' where role = 'admin';

do $$
begin
  if not exists (select 1 from public.profiles where role = 'direccion' and active) then
    update public.profiles
    set role = 'direccion'
    where id = (
      select id from public.profiles where active order by created_at asc limit 1
    );
  end if;
end $$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.app_role;
begin
  select case
    when exists (select 1 from public.profiles) then 'captura'::public.app_role
    else 'direccion'::public.app_role
  end into v_role;

  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), split_part(new.email, '@', 1)),
    v_role
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    active = true;
  return new;
end;
$$;

drop policy if exists manager_profiles_update on public.profiles;
create policy manager_profiles_update on public.profiles
  for update to authenticated
  using (public.is_manager())
  with check (public.is_manager());

create or replace function public.register_student_payment(
  p_student_id uuid,
  p_account_id uuid,
  p_method text,
  p_notes text,
  p_paid_on date,
  p_allocations jsonb
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_receipt_id uuid;
  v_income_id uuid;
  v_total numeric(12,2);
  v_item jsonb;
  v_charge public.charges%rowtype;
  v_amount numeric(12,2);
begin
  if not public.is_active_staff() then
    raise exception 'La cuenta no tiene acceso activo';
  end if;

  if p_method not in ('efectivo', 'transferencia', 'tarjeta', 'otro') then
    raise exception 'Forma de pago no valida';
  end if;

  select coalesce(sum((item ->> 'amount')::numeric), 0)
  into v_total
  from jsonb_array_elements(p_allocations) item;

  if v_total <= 0 then
    raise exception 'El total debe ser mayor a cero';
  end if;

  insert into public.receipts (
    student_id, account_id, payment_method, total, notes, created_by
  ) values (
    p_student_id, p_account_id, p_method, v_total, nullif(trim(p_notes), ''), auth.uid()
  ) returning id into v_receipt_id;

  insert into public.incomes (
    receipt_id, student_id, account_id, paid_on, amount, payment_method,
    reconciliation_status, created_by
  ) values (
    v_receipt_id, p_student_id, p_account_id, coalesce(p_paid_on, current_date),
    v_total, p_method,
    case when p_method = 'efectivo' then 'conciliado'::public.reconciliation_status
         else 'pendiente'::public.reconciliation_status end,
    auth.uid()
  ) returning id into v_income_id;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_amount := (v_item ->> 'amount')::numeric;
    select * into v_charge
    from public.charges
    where id = (v_item ->> 'charge_id')::uuid
    for update;

    if v_charge.id is null
      or v_charge.student_id <> p_student_id
      or v_amount <= 0
      or v_charge.paid_amount + v_amount > v_charge.net_amount then
      raise exception 'Aplicacion invalida para el cargo';
    end if;

    insert into public.payment_allocations (income_id, charge_id, amount)
    values (v_income_id, v_charge.id, v_amount);

    update public.charges
    set paid_amount = paid_amount + v_amount,
        status = case
          when paid_amount + v_amount = net_amount then 'pagado'::public.charge_status
          else 'parcial'::public.charge_status
        end
    where id = v_charge.id;
  end loop;

  return v_receipt_id;
end;
$$;

create or replace function public.register_cash_payment(
  p_student_id uuid,
  p_account_id uuid,
  p_method text,
  p_notes text,
  p_allocations jsonb
) returns uuid
language sql
security invoker
set search_path = public
as $$
  select public.register_student_payment(
    p_student_id, p_account_id, p_method, p_notes, current_date, p_allocations
  );
$$;

create or replace function public.import_student_finances(p_rows jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_item jsonb;
  v_cycle_id uuid;
  v_student_id uuid;
  v_contact_id uuid;
  v_concept_id uuid;
  v_charge_id uuid;
  v_account_id uuid;
  v_amount numeric(12,2);
  v_paid_amount numeric(12,2);
  v_due_on date;
  v_paid_on date;
  v_method text;
  v_students integer := 0;
  v_payments integer := 0;
begin
  if not public.is_active_staff() then
    raise exception 'La cuenta no tiene acceso activo';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'No hay filas para importar';
  end if;
  if jsonb_array_length(p_rows) > 500 then
    raise exception 'El limite es de 500 alumnos por archivo';
  end if;

  select id into v_cycle_id
  from public.school_cycles
  where active
  order by starts_on desc
  limit 1;
  if v_cycle_id is null then raise exception 'No hay un ciclo escolar activo'; end if;

  for v_item in select * from jsonb_array_elements(p_rows) loop
    if nullif(trim(v_item ->> 'enrollment'), '') is null
      or nullif(trim(v_item ->> 'first_name'), '') is null
      or nullif(trim(v_item ->> 'grade'), '') is null then
      raise exception 'Cada fila requiere matricula, nombre y grado';
    end if;

    insert into public.students (
      enrollment, first_name, last_name, level, grade, cycle_id, active
    ) values (
      trim(v_item ->> 'enrollment'),
      trim(v_item ->> 'first_name'),
      coalesce(nullif(trim(v_item ->> 'last_name'), ''), 'Pendiente'),
      coalesce(nullif(trim(v_item ->> 'level'), ''), 'Primaria'),
      trim(v_item ->> 'grade'),
      v_cycle_id,
      true
    )
    on conflict (enrollment, cycle_id) do update set
      first_name = excluded.first_name,
      last_name = excluded.last_name,
      level = excluded.level,
      grade = excluded.grade,
      active = true,
      updated_at = now()
    returning id into v_student_id;
    v_students := v_students + 1;

    if nullif(trim(v_item ->> 'tutor_name'), '') is not null then
      select id into v_contact_id
      from public.student_contacts
      where student_id = v_student_id and primary_contact
      order by id
      limit 1;

      if v_contact_id is null then
        insert into public.student_contacts (
          student_id, full_name, relationship, phone, email, primary_contact
        ) values (
          v_student_id, trim(v_item ->> 'tutor_name'), 'Tutor',
          nullif(trim(v_item ->> 'tutor_phone'), ''),
          nullif(trim(v_item ->> 'tutor_email'), ''), true
        );
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

    if v_amount > 0 then
      select id into v_concept_id
      from public.payment_concepts
      where lower(unaccent(name)) = lower(unaccent(coalesce(nullif(v_item ->> 'concept', ''), 'Colegiatura')))
        and active
      limit 1;
      if v_concept_id is null then
        raise exception 'El concepto % no existe', v_item ->> 'concept';
      end if;

      insert into public.charges (
        student_id, cycle_id, concept_id, gross_amount, due_on
      ) values (
        v_student_id, v_cycle_id, v_concept_id, v_amount, v_due_on
      )
      on conflict (student_id, cycle_id, cycle_month_id, concept_id) do update set
        gross_amount = greatest(public.charges.paid_amount, excluded.gross_amount),
        due_on = excluded.due_on
      returning id, paid_amount into v_charge_id, v_paid_amount;

      if v_paid_on is not null and v_paid_amount < v_amount then
        select id into v_account_id
        from public.accounts
        where active and kind = case when v_method = 'efectivo' then 'efectivo' else 'banco' end
        order by name
        limit 1;
        if v_account_id is null then raise exception 'No hay una cuenta financiera activa'; end if;

        perform public.register_student_payment(
          v_student_id,
          v_account_id,
          v_method,
          'Importado desde lista de alumnos',
          v_paid_on,
          jsonb_build_array(jsonb_build_object(
            'charge_id', v_charge_id,
            'amount', v_amount - v_paid_amount
          ))
        );
        v_payments := v_payments + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object('students', v_students, 'payments', v_payments);
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
  if not public.is_manager() then
    raise exception 'Solo Direccion puede cargar la prueba financiera';
  end if;

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

  select id into v_account_id from public.accounts where active and kind = 'efectivo' order by name limit 1;
  select id into v_category_id from public.expense_categories where active order by name limit 1;

  if v_account_id is not null and v_category_id is not null then
    insert into public.expenses (
      account_id, category_id, spent_on, supplier, description, subtotal,
      payment_method, created_by
    )
    select v_account_id, v_category_id, item.spent_on, item.supplier,
      item.description, item.subtotal, 'efectivo', auth.uid()
    from (values
      ('2026-06-03'::date, 'Papeleria Escolar', 'Prueba financiera - material para alumnos', 2460::numeric),
      ('2026-06-11'::date, 'JAPAY', 'Prueba financiera - servicio de agua', 1840::numeric),
      ('2026-06-20'::date, 'Mantenimiento CEI', 'Prueba financiera - mantenimiento', 3800::numeric)
    ) as item(spent_on, supplier, description, subtotal)
    where not exists (
      select 1 from public.expenses existing where existing.description = item.description
    );
    get diagnostics v_expenses = row_count;
  end if;

  return v_result || jsonb_build_object('expenses', v_expenses);
end;
$$;

create or replace view public.student_payment_status
with (security_invoker = true)
as
select
  student.id as student_id,
  student.enrollment,
  student.first_name,
  student.last_name,
  student.level,
  student.grade,
  contact.full_name as tutor_name,
  contact.phone as tutor_phone,
  charge.id as charge_id,
  concept.name as concept,
  charge.net_amount,
  charge.paid_amount,
  greatest(coalesce(charge.net_amount, 0) - coalesce(charge.paid_amount, 0), 0) as balance,
  charge.due_on,
  payment.paid_on,
  case
    when charge.id is null or charge.paid_amount < charge.net_amount then 'no_pagado'
    when charge.due_on is not null and payment.paid_on > charge.due_on then 'pagado_retraso'
    else 'pagado'
  end as payment_status
from public.students student
left join lateral (
  select c.*
  from public.charges c
  where c.student_id = student.id and c.status <> 'cancelado'
  order by c.due_on desc nulls last, c.created_at desc
  limit 1
) charge on true
left join public.payment_concepts concept on concept.id = charge.concept_id
left join lateral (
  select max(income.paid_on) as paid_on
  from public.payment_allocations allocation
  join public.incomes income on income.id = allocation.income_id and income.status = 'confirmado'
  where allocation.charge_id = charge.id
) payment on true
left join lateral (
  select full_name, phone
  from public.student_contacts
  where student_id = student.id
  order by primary_contact desc, id
  limit 1
) contact on true
where student.active;

grant select on public.student_payment_status to authenticated;
grant execute on function public.register_student_payment(uuid, uuid, text, text, date, jsonb) to authenticated;
grant execute on function public.register_cash_payment(uuid, uuid, text, text, jsonb) to authenticated;
grant execute on function public.import_student_finances(jsonb) to authenticated;
grant execute on function public.load_financial_demo() to authenticated;
