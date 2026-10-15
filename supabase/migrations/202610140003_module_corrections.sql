-- Correcciones para nómina, becas y presupuesto.
-- Las bajas son lógicas para conservar el historial y la auditoría.

create or replace function public.update_payroll_period_record(
  p_period_id uuid, p_starts_on date, p_ends_on date, p_account_id uuid, p_status public.movement_status
) returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if p_starts_on is null or p_ends_on is null or p_ends_on < p_starts_on then
    raise exception 'El periodo de nomina no es valido';
  end if;
  update public.payroll_periods set starts_on = p_starts_on, ends_on = p_ends_on,
    account_id = p_account_id, status = coalesce(p_status, status)
  where id = p_period_id and status <> 'cancelado';
  if not found then raise exception 'El periodo no existe o ya esta cancelado'; end if;
  return jsonb_build_object('period_id', p_period_id);
end;
$$;

create or replace function public.cancel_payroll_record(p_period_id uuid, p_reason text)
returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Indica el motivo de la cancelacion'; end if;
  update public.payroll_periods set status = 'cancelado'
  where id = p_period_id and status <> 'cancelado';
  if not found then raise exception 'El periodo no existe o ya esta cancelado'; end if;
  return jsonb_build_object('period_id', p_period_id);
end;
$$;

create or replace function public.update_scholarship_record(
  p_scholarship_id uuid, p_percentage numeric, p_starts_on date, p_ends_on date,
  p_concept_id uuid, p_active boolean
) returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if p_percentage is null or p_percentage < 0 or p_percentage > 100 or p_starts_on is null
    or p_ends_on is null or p_ends_on < p_starts_on then
    raise exception 'La beca no tiene datos validos';
  end if;
  update public.scholarships set percentage = p_percentage, starts_on = p_starts_on,
    ends_on = p_ends_on, concept_id = p_concept_id, active = coalesce(p_active, active)
  where id = p_scholarship_id;
  if not found then raise exception 'La beca no existe'; end if;
  return jsonb_build_object('scholarship_id', p_scholarship_id);
end;
$$;

create or replace function public.cancel_scholarship_record(p_scholarship_id uuid, p_reason text)
returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Indica el motivo de la cancelacion'; end if;
  update public.scholarships set active = false where id = p_scholarship_id and active;
  if not found then raise exception 'La beca no existe o ya esta inactiva'; end if;
  return jsonb_build_object('scholarship_id', p_scholarship_id);
end;
$$;

create or replace function public.update_budget_record(
  p_budget_id uuid, p_name text, p_status public.movement_status
) returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if nullif(trim(p_name), '') is null then raise exception 'El nombre del presupuesto es obligatorio'; end if;
  update public.budgets set name = trim(p_name), status = coalesce(p_status, status)
  where id = p_budget_id and status <> 'cancelado';
  if not found then raise exception 'El presupuesto no existe o ya esta cancelado'; end if;
  return jsonb_build_object('budget_id', p_budget_id);
end;
$$;

create or replace function public.cancel_budget_record(p_budget_id uuid, p_reason text)
returns jsonb language plpgsql security invoker set search_path = public
as $$
begin
  if not public.is_active_staff() then raise exception 'La cuenta no tiene acceso activo'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Indica el motivo de la cancelacion'; end if;
  update public.budgets set status = 'cancelado' where id = p_budget_id and status <> 'cancelado';
  if not found then raise exception 'El presupuesto no existe o ya esta cancelado'; end if;
  return jsonb_build_object('budget_id', p_budget_id);
end;
$$;

grant execute on function public.update_payroll_period_record(uuid,date,date,uuid,public.movement_status) to authenticated;
grant execute on function public.cancel_payroll_record(uuid,text) to authenticated;
grant execute on function public.update_scholarship_record(uuid,numeric,date,date,uuid,boolean) to authenticated;
grant execute on function public.cancel_scholarship_record(uuid,text) to authenticated;
grant execute on function public.update_budget_record(uuid,text,public.movement_status) to authenticated;
grant execute on function public.cancel_budget_record(uuid,text) to authenticated;
