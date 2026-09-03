-- Corrige pagos historicos realizados tarde antes de incorporar los recargos.
-- El recargo predeterminado es 10% y se integra al cargo, ingreso y recibo.

do $$
declare
  item record;
  v_base numeric(12,2);
  v_fee numeric(12,2);
begin
  for item in
    select
      charge.id as charge_id,
      charge.gross_amount,
      charge.paid_amount,
      income.id as income_id,
      income.receipt_id,
      coalesce(fee.amount, concept.base_amount, charge.gross_amount) as configured_base
    from public.charges charge
    join public.students student on student.id = charge.student_id
    join public.payment_concepts concept on concept.id = charge.concept_id
    left join public.fees fee
      on fee.cycle_id = charge.cycle_id
      and fee.concept_id = charge.concept_id
      and fee.level = student.level
      and fee.grade = student.grade
    join lateral (
      select registered_income.*
      from public.payment_allocations allocation
      join public.incomes registered_income on registered_income.id = allocation.income_id
      where allocation.charge_id = charge.id
        and registered_income.status = 'confirmado'
        and registered_income.paid_on > charge.due_on
      order by registered_income.paid_on desc, registered_income.created_at desc
      limit 1
    ) income on true
    where charge.late_fee_amount = 0
      and charge.due_on is not null
      and charge.paid_amount = charge.net_amount
      and charge.status = 'pagado'
  loop
    v_base := least(item.gross_amount, item.configured_base);
    v_fee := round(v_base * 0.10, 2);

    if v_fee > 0 then
      update public.charges
      set gross_amount = gross_amount + v_fee,
          late_fee_amount = v_fee
      where id = item.charge_id;

      update public.payment_allocations
      set amount = amount + v_fee
      where income_id = item.income_id and charge_id = item.charge_id;

      update public.incomes
      set amount = amount + v_fee
      where id = item.income_id;

      update public.receipts
      set total = total + v_fee,
          notes = case
            when coalesce(notes, '') ilike '%recargo%' then notes
            else concat_ws(' · ', nullif(notes, ''), 'Incluye recargo por atraso')
          end
      where id = item.receipt_id;

      update public.charges
      set paid_amount = paid_amount + v_fee,
          status = 'pagado'
      where id = item.charge_id;
    end if;
  end loop;
end;
$$;
