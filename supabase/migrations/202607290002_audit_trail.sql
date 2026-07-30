-- Historial de respaldo lógico para operaciones escolares y financieras.
-- Supabase mantiene el respaldo físico de la base; este historial permite
-- reconstruir quién cambió un registro y conservar el valor anterior.
create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record_id uuid;
begin
  v_record_id := coalesce((to_jsonb(new)->>'id')::uuid, (to_jsonb(old)->>'id')::uuid);
  insert into public.audit_log(table_name, record_id, action, old_data, new_data, performed_by)
  values (
    tg_table_name,
    v_record_id,
    tg_op,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end,
    auth.uid()
  );
  return coalesce(new, old);
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'students','student_contacts','charges','receipts','incomes',
    'payment_allocations','expenses','transfers','bank_movements',
    'payroll_periods','payroll_items','budgets','budget_lines',
    'scholarships','pre_enrollments','attachments'
  ] loop
    execute format('drop trigger if exists audit_row_change_trigger on public.%I', v_table);
    execute format(
      'create trigger audit_row_change_trigger after insert or update or delete on public.%I for each row execute function public.audit_row_change()',
      v_table
    );
  end loop;
end $$;

create index if not exists audit_log_table_record_idx
  on public.audit_log(table_name, record_id, performed_at desc);
