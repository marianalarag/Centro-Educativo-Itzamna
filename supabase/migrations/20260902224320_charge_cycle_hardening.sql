-- Asocia cargos recurrentes al mes escolar y fija el precio desde catalogos.

create or replace function public.create_student_charge(
  p_student_id uuid, p_enrollment text, p_first_name text, p_last_name text,
  p_level text, p_grade text, p_tutor_name text, p_tutor_phone text,
  p_concept_id uuid, p_due_on date, p_paid_on date, p_base_amount numeric,
  p_late_fee_rate numeric default 10, p_payment_method text default 'efectivo'
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
    insert into public.students (enrollment, first_name, last_name, level, grade, cycle_id)
    values (upper(trim(p_enrollment)), trim(p_first_name), trim(p_last_name),
      coalesce(nullif(trim(p_level), ''), 'Primaria'), trim(p_grade), v_cycle_id)
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
  if p_paid_on is not null and p_paid_on > p_due_on then
    v_late_fee := round(v_base * p_late_fee_rate / 100, 2);
  end if;

  select * into v_charge from public.charges
  where student_id = v_student_id and cycle_id = v_cycle_id and concept_id = p_concept_id
    and cycle_month_id is not distinct from v_cycle_month_id
    and status in ('pendiente','parcial','vencido')
  order by created_at desc limit 1 for update;

  if v_charge.id is null then
    if exists (select 1 from public.charges where student_id = v_student_id and cycle_id = v_cycle_id
      and concept_id = p_concept_id and cycle_month_id is not distinct from v_cycle_month_id
      and status = 'pagado') then
      raise exception 'Este concepto ya esta pagado para el periodo seleccionado';
    end if;
    insert into public.charges (student_id, cycle_id, cycle_month_id, concept_id, gross_amount, late_fee_amount, due_on, status)
    values (v_student_id, v_cycle_id, v_cycle_month_id, p_concept_id, v_base + v_late_fee, v_late_fee, p_due_on,
      case when p_paid_on is null and p_due_on < current_date then 'vencido'::public.charge_status else 'pendiente'::public.charge_status end)
    returning * into v_charge;
  elsif v_charge.paid_amount > 0 then
    raise exception 'El cargo tiene un pago parcial; termina de cobrarlo desde su saldo';
  else
    update public.charges set gross_amount = v_base + v_late_fee, late_fee_amount = v_late_fee,
      due_on = p_due_on, cycle_month_id = v_cycle_month_id,
      status = case when p_paid_on is null and p_due_on < current_date then 'vencido'::public.charge_status else 'pendiente'::public.charge_status end
    where id = v_charge.id returning * into v_charge;
  end if;

  if p_paid_on is not null then
    select id into v_account_id from public.accounts
    where active and kind = case when p_payment_method = 'transferencia' then 'banco' else 'efectivo' end
    order by name limit 1;
    if v_account_id is null then raise exception 'No hay una cuenta financiera compatible'; end if;
    select public.register_student_payment(v_student_id, v_account_id, p_payment_method,
      case when v_late_fee > 0 then 'Pago con recargo por atraso' else 'Cobro registrado' end,
      p_paid_on, jsonb_build_array(jsonb_build_object('charge_id', v_charge.id, 'amount', v_charge.net_amount)))
    into v_receipt_id;
  end if;

  return jsonb_build_object('student_id',v_student_id,'charge_id',v_charge.id,'receipt_id',v_receipt_id,
    'base_amount',v_base,'late_fee_amount',v_late_fee,'total',v_base + v_late_fee,
    'payment_status',case when p_paid_on is null then 'no_pagado' when p_paid_on > p_due_on then 'pagado_retraso' else 'pagado' end);
end;
$$;
