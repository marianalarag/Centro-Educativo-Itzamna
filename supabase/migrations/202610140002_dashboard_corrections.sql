-- Operaciones de corrección desde el dashboard.
-- Los movimientos financieros se cancelan, no se eliminan, para conservar auditoría.

create or replace function public.update_student_record(
  p_student_id uuid, p_enrollment text, p_first_name text, p_last_name text,
  p_level text, p_grade text, p_tutor_name text default null, p_tutor_phone text default null
) returns jsonb
language plpgsql security invoker set search_path = public
as $$
declare
  v_contact_id uuid;
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if nullif(trim(p_enrollment), '') is null or nullif(trim(p_first_name), '') is null
    or nullif(trim(p_last_name), '') is null or nullif(trim(p_grade), '') is null then
    raise exception 'Completa matricula, nombre, apellidos y grado del alumno';
  end if;

  update public.students set
    enrollment = upper(trim(p_enrollment)), first_name = trim(p_first_name),
    last_name = trim(p_last_name), level = coalesce(nullif(trim(p_level), ''), 'Primaria'),
    grade = trim(p_grade), updated_at = now()
  where id = p_student_id and active;
  if not found then raise exception 'El alumno no existe o ya esta dado de baja'; end if;

  if nullif(trim(p_tutor_name), '') is not null then
    select id into v_contact_id from public.student_contacts
    where student_id = p_student_id and primary_contact
    order by id limit 1;
    if v_contact_id is null then
      insert into public.student_contacts (student_id, full_name, relationship, phone, primary_contact)
      values (p_student_id, trim(p_tutor_name), 'Tutor', nullif(trim(p_tutor_phone), ''), true);
    else
      update public.student_contacts set full_name = trim(p_tutor_name),
        phone = nullif(trim(p_tutor_phone), '') where id = v_contact_id;
    end if;
  end if;
  return jsonb_build_object('student_id', p_student_id);
end;
$$;

create or replace function public.deactivate_student(p_student_id uuid, p_reason text default null)
returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  update public.students set active = false,
    notes = case when nullif(trim(p_reason), '') is null then notes
      when nullif(trim(notes), '') is null then trim(p_reason)
      else notes || E'\nBaja: ' || trim(p_reason) end,
    updated_at = now()
  where id = p_student_id and active;
  if not found then raise exception 'El alumno no existe o ya esta dado de baja'; end if;
  return jsonb_build_object('student_id', p_student_id, 'active', false);
end;
$$;

create or replace function public.update_income_record(
  p_income_id uuid, p_paid_on date, p_amount numeric, p_payment_method text, p_bank_reference text
) returns jsonb language plpgsql security invoker set search_path = public
as $$
declare
  v_income public.incomes%rowtype;
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if p_paid_on is null or p_amount is null or p_amount <= 0 then raise exception 'Fecha e importe son obligatorios'; end if;
  select * into v_income from public.incomes where id = p_income_id for update;
  if v_income.id is null then raise exception 'El ingreso no existe'; end if;
  if v_income.status = 'cancelado' then raise exception 'El ingreso ya esta cancelado'; end if;
  if v_income.receipt_id is not null and p_amount <> v_income.amount then
    raise exception 'El importe de un recibo confirmado no se puede cambiar; cancela el movimiento y registra el correcto';
  end if;
  update public.incomes set paid_on = p_paid_on, amount = p_amount,
    payment_method = lower(trim(p_payment_method)), bank_reference = nullif(trim(p_bank_reference), '')
  where id = p_income_id;
  if v_income.receipt_id is not null then
    update public.receipts set payment_method = lower(trim(p_payment_method))
    where id = v_income.receipt_id;
  end if;
  return jsonb_build_object('income_id', p_income_id);
end;
$$;

create or replace function public.cancel_income_record(p_income_id uuid, p_reason text)
returns jsonb language plpgsql security invoker set search_path = public
as $$
declare
  v_income public.incomes%rowtype;
  v_allocation record;
  v_allocations integer := 0;
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Indica el motivo de la cancelacion'; end if;
  select * into v_income from public.incomes where id = p_income_id for update;
  if v_income.id is null then raise exception 'El ingreso no existe'; end if;
  if v_income.status = 'cancelado' then raise exception 'El ingreso ya esta cancelado'; end if;

  for v_allocation in select charge_id, amount from public.payment_allocations where income_id = p_income_id loop
    update public.charges set paid_amount = greatest(0, paid_amount - v_allocation.amount),
      status = case
        when greatest(0, paid_amount - v_allocation.amount) = 0 and due_on is not null and due_on < current_date then 'vencido'::public.charge_status
        when greatest(0, paid_amount - v_allocation.amount) = 0 then 'pendiente'::public.charge_status
        else 'parcial'::public.charge_status end
    where id = v_allocation.charge_id;
    v_allocations := v_allocations + 1;
  end loop;

  update public.incomes set status = 'cancelado', reconciliation_status = 'no_identificado',
    bank_reference = concat_ws(' | ', bank_reference, 'Cancelado: ' || trim(p_reason))
  where id = p_income_id;
  if v_income.receipt_id is not null then
    update public.receipts set status = 'cancelado', cancelled_by = auth.uid(), cancelled_at = now(),
      notes = concat_ws(' | ', notes, 'Cancelado: ' || trim(p_reason))
    where id = v_income.receipt_id;
  end if;
  update public.bank_movements set income_id = null, status = 'no_identificado'
  where income_id = p_income_id;
  return jsonb_build_object('income_id', p_income_id, 'reversed_allocations', v_allocations);
end;
$$;

create or replace function public.update_expense_record(
  p_expense_id uuid, p_spent_on date, p_supplier text, p_description text,
  p_subtotal numeric, p_tax numeric, p_payment_method text, p_account_id uuid, p_category_id uuid
) returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if p_spent_on is null or nullif(trim(p_description), '') is null or p_subtotal is null or p_subtotal < 0
    or p_tax is null or p_tax < 0 or p_account_id is null or p_category_id is null then
    raise exception 'Completa fecha, descripcion, importes, cuenta y partida';
  end if;
  update public.expenses set spent_on = p_spent_on, supplier = nullif(trim(p_supplier), ''),
    description = trim(p_description), subtotal = p_subtotal, tax = p_tax,
    payment_method = lower(trim(p_payment_method)), account_id = p_account_id, category_id = p_category_id
  where id = p_expense_id and status <> 'cancelado';
  if not found then raise exception 'El egreso no existe o ya esta cancelado'; end if;
  return jsonb_build_object('expense_id', p_expense_id);
end;
$$;

create or replace function public.cancel_expense_record(p_expense_id uuid, p_reason text)
returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Indica el motivo de la cancelacion'; end if;
  update public.expenses set status = 'cancelado', description = description || ' | Cancelado: ' || trim(p_reason)
  where id = p_expense_id and status <> 'cancelado';
  if not found then raise exception 'El egreso no existe o ya esta cancelado'; end if;
  return jsonb_build_object('expense_id', p_expense_id);
end;
$$;

create or replace function public.update_transfer_record(
  p_transfer_id uuid, p_transferred_on date, p_amount numeric, p_reason text,
  p_source_account_id uuid, p_destination_account_id uuid
) returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if p_transferred_on is null or p_amount is null or p_amount <= 0 or nullif(trim(p_reason), '') is null
    or p_source_account_id is null or p_destination_account_id is null or p_source_account_id = p_destination_account_id then
    raise exception 'Completa fecha, importe, motivo y cuentas distintas';
  end if;
  update public.transfers set transferred_on = p_transferred_on, amount = p_amount,
    reason = trim(p_reason), source_account_id = p_source_account_id, destination_account_id = p_destination_account_id
  where id = p_transfer_id and status <> 'cancelado';
  if not found then raise exception 'El traspaso no existe o ya esta cancelado'; end if;
  return jsonb_build_object('transfer_id', p_transfer_id);
end;
$$;

create or replace function public.cancel_transfer_record(p_transfer_id uuid, p_reason text)
returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Indica el motivo de la cancelacion'; end if;
  update public.transfers set status = 'cancelado', reason = reason || ' | Cancelado: ' || trim(p_reason)
  where id = p_transfer_id and status <> 'cancelado';
  if not found then raise exception 'El traspaso no existe o ya esta cancelado'; end if;
  return jsonb_build_object('transfer_id', p_transfer_id);
end;
$$;

create or replace function public.update_bank_movement_record(
  p_movement_id uuid, p_bank_date date, p_description text, p_reference text,
  p_amount numeric, p_status public.reconciliation_status
) returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if p_bank_date is null or nullif(trim(p_description), '') is null or p_amount is null or p_amount = 0 then
    raise exception 'Completa fecha, descripcion e importe';
  end if;
  if p_status = 'conciliado' and not exists (
    select 1 from public.bank_movements where id = p_movement_id and income_id is not null
  ) then
    raise exception 'Para conciliar selecciona un ingreso relacionado';
  end if;
  update public.bank_movements set bank_date = p_bank_date, description = trim(p_description),
    reference = nullif(trim(p_reference), ''), amount = p_amount, status = coalesce(p_status, status)
  where id = p_movement_id;
  if not found then raise exception 'El movimiento bancario no existe'; end if;
  return jsonb_build_object('movement_id', p_movement_id);
end;
$$;

create or replace function public.mark_bank_movement_duplicate(p_movement_id uuid, p_reason text)
returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Indica el motivo'; end if;
  update public.bank_movements set status = 'duplicado', description = description || ' | Marcado como duplicado: ' || trim(p_reason)
  where id = p_movement_id;
  if not found then raise exception 'El movimiento bancario no existe'; end if;
  return jsonb_build_object('movement_id', p_movement_id, 'status', 'duplicado');
end;
$$;

create or replace function public.reconcile_bank_movement(p_movement_id uuid, p_income_id uuid)
returns jsonb language plpgsql security invoker set search_path = public
as $$
declare
  v_movement public.bank_movements%rowtype;
  v_income public.incomes%rowtype;
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  select * into v_movement from public.bank_movements where id = p_movement_id for update;
  if v_movement.id is null then raise exception 'El movimiento bancario no existe'; end if;
  if p_income_id is null then
    update public.bank_movements set income_id = null, status = 'no_identificado' where id = p_movement_id;
  else
    select * into v_income from public.incomes where id = p_income_id and status = 'confirmado';
    if v_income.id is null then raise exception 'El ingreso no existe o esta cancelado'; end if;
    if abs(v_movement.amount) <> v_income.amount then raise exception 'El importe del banco no coincide con el ingreso'; end if;
    update public.bank_movements set income_id = p_income_id, status = 'conciliado' where id = p_movement_id;
    update public.incomes set reconciliation_status = 'conciliado' where id = p_income_id;
  end if;
  return jsonb_build_object('movement_id', p_movement_id, 'income_id', p_income_id);
end;
$$;

create or replace function public.update_charge_record(
  p_charge_id uuid, p_due_on date, p_gross_amount numeric
) returns jsonb language plpgsql security invoker set search_path = public
as $$
declare
  v_charge public.charges%rowtype;
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if p_due_on is null or p_gross_amount is null or p_gross_amount <= 0 then raise exception 'Completa vencimiento e importe'; end if;
  select * into v_charge from public.charges where id = p_charge_id for update;
  if v_charge.id is null or v_charge.status = 'cancelado' then raise exception 'El cargo no existe o esta cancelado'; end if;
  if p_gross_amount < v_charge.paid_amount then raise exception 'El importe no puede ser menor que lo ya pagado'; end if;
  update public.charges set due_on = p_due_on, gross_amount = p_gross_amount,
    status = case when paid_amount >= p_gross_amount then 'pagado'::public.charge_status
      when p_due_on < current_date then 'vencido'::public.charge_status else 'pendiente'::public.charge_status end
  where id = p_charge_id;
  return jsonb_build_object('charge_id', p_charge_id);
end;
$$;

create or replace function public.cancel_charge_record(p_charge_id uuid, p_reason text)
returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Indica el motivo de la cancelacion'; end if;
  if exists (select 1 from public.charges where id = p_charge_id and paid_amount > 0) then
    raise exception 'Este cargo ya tiene pagos; cancela primero el ingreso relacionado';
  end if;
  update public.charges set status = 'cancelado' where id = p_charge_id and status <> 'cancelado';
  if not found then raise exception 'El cargo no existe o ya esta cancelado'; end if;
  return jsonb_build_object('charge_id', p_charge_id);
end;
$$;

drop policy if exists staff_receipts_write on public.receipts;
create policy staff_receipts_insert on public.receipts for insert to authenticated
  with check (public.is_active_staff() and created_by = auth.uid());
create policy staff_receipts_update on public.receipts for update to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());

drop policy if exists staff_incomes_write on public.incomes;
create policy staff_incomes_insert on public.incomes for insert to authenticated
  with check (public.is_active_staff() and created_by = auth.uid());
create policy staff_incomes_update on public.incomes for update to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());

drop policy if exists staff_expenses_write on public.expenses;
create policy staff_expenses_insert on public.expenses for insert to authenticated
  with check (public.is_active_staff() and created_by = auth.uid());
create policy staff_expenses_update on public.expenses for update to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());

drop policy if exists staff_transfers_write on public.transfers;
create policy staff_transfers_insert on public.transfers for insert to authenticated
  with check (public.is_active_staff() and created_by = auth.uid());
create policy staff_transfers_update on public.transfers for update to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());

drop policy if exists staff_write on public.bank_movements;
create policy staff_bank_movements_insert on public.bank_movements for insert to authenticated
  with check (public.is_active_staff() and imported_by = auth.uid());
create policy staff_bank_movements_update on public.bank_movements for update to authenticated
  using (public.is_active_staff()) with check (public.is_active_staff());

grant execute on function public.update_student_record(uuid,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.deactivate_student(uuid,text) to authenticated;
grant execute on function public.update_income_record(uuid,date,numeric,text,text) to authenticated;
grant execute on function public.cancel_income_record(uuid,text) to authenticated;
grant execute on function public.update_expense_record(uuid,date,text,text,numeric,numeric,text,uuid,uuid) to authenticated;
grant execute on function public.cancel_expense_record(uuid,text) to authenticated;
grant execute on function public.update_transfer_record(uuid,date,numeric,text,uuid,uuid) to authenticated;
grant execute on function public.cancel_transfer_record(uuid,text) to authenticated;
grant execute on function public.update_bank_movement_record(uuid,date,text,text,numeric,public.reconciliation_status) to authenticated;
grant execute on function public.mark_bank_movement_duplicate(uuid,text) to authenticated;
grant execute on function public.reconcile_bank_movement(uuid,uuid) to authenticated;
grant execute on function public.update_charge_record(uuid,date,numeric) to authenticated;
grant execute on function public.cancel_charge_record(uuid,text) to authenticated;
