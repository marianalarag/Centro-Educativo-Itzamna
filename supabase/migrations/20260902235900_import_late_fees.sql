-- Aplica recargo configurable a pagos atrasados importados desde CSV o Excel.

create or replace function public.import_student_finances(p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_item jsonb;
  v_cycle_id uuid;
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
    if nullif(trim(v_item ->> 'enrollment'), '') is null or nullif(trim(v_item ->> 'first_name'), '') is null
      or nullif(trim(v_item ->> 'grade'), '') is null then raise exception 'Cada fila requiere matricula, nombre y grado'; end if;

    insert into public.students (enrollment, first_name, last_name, level, grade, cycle_id, active)
    values (trim(v_item ->> 'enrollment'), trim(v_item ->> 'first_name'),
      coalesce(nullif(trim(v_item ->> 'last_name'), ''), 'Pendiente'),
      coalesce(nullif(trim(v_item ->> 'level'), ''), 'Primaria'), trim(v_item ->> 'grade'), v_cycle_id, true)
    on conflict (enrollment, cycle_id) do update set first_name=excluded.first_name, last_name=excluded.last_name,
      level=excluded.level, grade=excluded.grade, active=true, updated_at=now()
    returning id into v_student_id;
    v_students := v_students + 1;

    if nullif(trim(v_item ->> 'tutor_name'), '') is not null then
      select id into v_contact_id from public.student_contacts
      where student_id=v_student_id and primary_contact order by id limit 1;
      if v_contact_id is null then
        insert into public.student_contacts (student_id,full_name,relationship,phone,email,primary_contact)
        values (v_student_id,trim(v_item ->> 'tutor_name'),'Tutor',nullif(trim(v_item ->> 'tutor_phone'),''),
          nullif(trim(v_item ->> 'tutor_email'),''),true);
      else
        update public.student_contacts set full_name=trim(v_item ->> 'tutor_name'),
          phone=nullif(trim(v_item ->> 'tutor_phone'),''), email=nullif(trim(v_item ->> 'tutor_email'),'')
        where id=v_contact_id;
      end if;
    end if;

    v_amount := coalesce(nullif(v_item ->> 'amount','')::numeric,0);
    v_due_on := nullif(v_item ->> 'due_on','')::date;
    v_paid_on := nullif(v_item ->> 'paid_on','')::date;
    v_method := coalesce(nullif(v_item ->> 'payment_method',''),'efectivo');
    v_late_rate := coalesce(nullif(v_item ->> 'late_fee_rate','')::numeric,10);
    if v_late_rate < 0 or v_late_rate > 100 then raise exception 'El recargo debe estar entre 0 y 100'; end if;
    v_late_fee := case when v_paid_on is not null and v_due_on is not null and v_paid_on > v_due_on
      then round(v_amount * v_late_rate / 100,2) else 0 end;
    v_total := v_amount + v_late_fee;

    if v_amount > 0 then
      select id into v_concept_id from public.payment_concepts
      where lower(unaccent(name))=lower(unaccent(coalesce(nullif(v_item ->> 'concept',''),'Colegiatura'))) and active limit 1;
      if v_concept_id is null then raise exception 'El concepto % no existe',v_item ->> 'concept'; end if;

      insert into public.charges (student_id,cycle_id,concept_id,gross_amount,late_fee_amount,due_on)
      values (v_student_id,v_cycle_id,v_concept_id,v_total,v_late_fee,v_due_on)
      on conflict (student_id,cycle_id,cycle_month_id,concept_id) do update set
        gross_amount=greatest(public.charges.paid_amount,excluded.gross_amount),
        late_fee_amount=case when public.charges.paid_amount=0 then excluded.late_fee_amount else public.charges.late_fee_amount end,
        due_on=excluded.due_on
      returning id,paid_amount into v_charge_id,v_paid_amount;

      if v_paid_on is not null and v_paid_amount < v_total then
        select id into v_account_id from public.accounts
        where active and kind=case when v_method='efectivo' then 'efectivo' else 'banco' end order by name limit 1;
        if v_account_id is null then raise exception 'No hay una cuenta financiera activa'; end if;
        perform public.register_student_payment(v_student_id,v_account_id,v_method,
          case when v_late_fee > 0 then 'Importado con recargo por atraso' else 'Importado desde lista de alumnos' end,
          v_paid_on,jsonb_build_array(jsonb_build_object('charge_id',v_charge_id,'amount',v_total-v_paid_amount)));
        v_payments := v_payments + 1;
        v_late_fees := v_late_fees + v_late_fee;
      end if;
    end if;
  end loop;
  return jsonb_build_object('students',v_students,'payments',v_payments,'late_fees',v_late_fees);
end;
$$;
