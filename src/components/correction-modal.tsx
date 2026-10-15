"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import { X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

type Kind = "student" | "charge" | "income" | "expense" | "transfer" | "bank";
type Account = { id: string; name: string };
type Category = { id: string; name: string; type: string };

const titles: Record<Kind, string> = {
  student: "Editar alumno", charge: "Editar cargo", income: "Editar ingreso",
  expense: "Editar egreso", transfer: "Editar traspaso", bank: "Editar movimiento bancario",
};

export function CorrectionModal({ action, close }: { action: string; close: () => void }) {
  const supabase = useMemo(() => createClient(), []);
  const [, kindValue, id, operationValue] = action.split(":");
  const kind = kindValue as Kind;
  const operation = operationValue ?? "edit";
  const [loading, setLoading] = useState(operation === "edit");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [reason, setReason] = useState("");
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [accountId, setAccountId] = useState("");
  const [destinationAccountId, setDestinationAccountId] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [enrollment, setEnrollment] = useState("");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [level, setLevel] = useState("Primaria");
  const [grade, setGrade] = useState("");
  const [tutorName, setTutorName] = useState("");
  const [tutorPhone, setTutorPhone] = useState("");
  const [date, setDate] = useState("");
  const [amount, setAmount] = useState("");
  const [paymentMethod, setPaymentMethod] = useState("efectivo");
  const [bankReference, setBankReference] = useState("");
  const [supplier, setSupplier] = useState("");
  const [description, setDescription] = useState("");
  const [tax, setTax] = useState("0");
  const [status, setStatus] = useState("pendiente");

  useEffect(() => {
    if (operation !== "edit" || !id) return;
    async function loadRecord() {
      try {
        if (kind === "student") {
          const [{ data: student, error }, { data: contact }] = await Promise.all([
            supabase.from("students").select("enrollment,first_name,last_name,level,grade").eq("id", id).single(),
            supabase.from("student_contacts").select("full_name,phone").eq("student_id", id).eq("primary_contact", true).limit(1).maybeSingle(),
          ]);
          if (error) throw error;
          setEnrollment(student.enrollment); setFirstName(student.first_name); setLastName(student.last_name);
          setLevel(student.level); setGrade(student.grade); setTutorName(contact?.full_name ?? ""); setTutorPhone(contact?.phone ?? "");
        } else if (kind === "charge") {
          const { data, error } = await supabase.from("charges").select("due_on,gross_amount,paid_amount").eq("id", id).single();
          if (error) throw error;
          setDate(data.due_on ?? ""); setAmount(String(data.gross_amount ?? ""));
        } else if (kind === "income") {
          const { data, error } = await supabase.from("incomes").select("paid_on,amount,payment_method,bank_reference").eq("id", id).single();
          if (error) throw error;
          setDate(data.paid_on); setAmount(String(data.amount)); setPaymentMethod(data.payment_method); setBankReference(data.bank_reference ?? "");
        } else if (kind === "expense") {
          const [{ data, error }, { data: accountRows }, { data: categoryRows }] = await Promise.all([
            supabase.from("expenses").select("spent_on,account_id,category_id,supplier,description,subtotal,tax,payment_method").eq("id", id).single(),
            supabase.from("accounts").select("id,name").eq("active", true).order("name"),
            supabase.from("expense_categories").select("id,name,type").eq("active", true).order("name"),
          ]);
          if (error) throw error;
          setAccounts((accountRows ?? []) as Account[]); setCategories((categoryRows ?? []) as Category[]);
          setAccountId(data.account_id); setCategoryId(data.category_id); setDate(data.spent_on); setSupplier(data.supplier ?? "");
          setDescription(data.description); setAmount(String(data.subtotal)); setTax(String(data.tax)); setPaymentMethod(data.payment_method);
        } else if (kind === "transfer") {
          const [{ data, error }, { data: accountRows }] = await Promise.all([
            supabase.from("transfers").select("transferred_on,source_account_id,destination_account_id,amount,reason").eq("id", id).single(),
            supabase.from("accounts").select("id,name").eq("active", true).order("name"),
          ]);
          if (error) throw error;
          setAccounts((accountRows ?? []) as Account[]); setAccountId(data.source_account_id); setDestinationAccountId(data.destination_account_id);
          setDate(data.transferred_on); setAmount(String(data.amount)); setDescription(data.reason);
        } else if (kind === "bank") {
          const { data, error } = await supabase.from("bank_movements").select("bank_date,description,reference,amount,status").eq("id", id).single();
          if (error) throw error;
          setDate(data.bank_date); setDescription(data.description); setBankReference(data.reference ?? ""); setAmount(String(data.amount)); setStatus(data.status);
        }
      } catch (error) {
        setMessage(error instanceof Error ? error.message : "No se pudo cargar el registro.");
      } finally {
        setLoading(false);
      }
    }
    loadRecord();
  }, [id, kind, operation, supabase]);

  useEffect(() => {
    if (operation !== "edit" || (kind !== "expense" && kind !== "transfer")) return;
    if (accounts.length || categories.length) return;
    Promise.all([
      supabase.from("accounts").select("id,name").eq("active", true).order("name"),
      kind === "expense" ? supabase.from("expense_categories").select("id,name,type").eq("active", true).order("name") : Promise.resolve({ data: [] as Category[] }),
    ]).then(([accountResult, categoryResult]) => {
      setAccounts((accountResult.data ?? []) as Account[]);
      setCategories((categoryResult.data ?? []) as Category[]);
    });
  }, [accounts.length, categories.length, kind, operation, supabase]);

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true); setMessage("");
    try {
      let result;
      if (operation === "deactivate") result = await supabase.rpc("deactivate_student", { p_student_id: id, p_reason: reason });
      else if (operation === "cancel") result = await supabase.rpc(`cancel_${kind}_record`, { [`p_${kind}_id`]: id, p_reason: reason });
      else if (operation === "duplicate") result = await supabase.rpc("mark_bank_movement_duplicate", { p_movement_id: id, p_reason: reason });
      else if (kind === "student") result = await supabase.rpc("update_student_record", {
        p_student_id: id, p_enrollment: enrollment, p_first_name: firstName, p_last_name: lastName,
        p_level: level, p_grade: grade, p_tutor_name: tutorName, p_tutor_phone: tutorPhone,
      });
      else if (kind === "charge") result = await supabase.rpc("update_charge_record", { p_charge_id: id, p_due_on: date, p_gross_amount: Number(amount) });
      else if (kind === "income") result = await supabase.rpc("update_income_record", { p_income_id: id, p_paid_on: date, p_amount: Number(amount), p_payment_method: paymentMethod, p_bank_reference: bankReference });
      else if (kind === "expense") result = await supabase.rpc("update_expense_record", {
        p_expense_id: id, p_spent_on: date, p_supplier: supplier, p_description: description,
        p_subtotal: Number(amount), p_tax: Number(tax), p_payment_method: paymentMethod, p_account_id: accountId, p_category_id: categoryId,
      });
      else if (kind === "transfer") result = await supabase.rpc("update_transfer_record", {
        p_transfer_id: id, p_transferred_on: date, p_amount: Number(amount), p_reason: description,
        p_source_account_id: accountId, p_destination_account_id: destinationAccountId,
      });
      else result = await supabase.rpc("update_bank_movement_record", {
        p_movement_id: id, p_bank_date: date, p_description: description, p_reference: bankReference,
        p_amount: Number(amount), p_status: status,
      });
      if (result.error) throw result.error;
      window.dispatchEvent(new Event("cei:data-changed"));
      close();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo guardar el cambio.");
    } finally {
      setBusy(false);
    }
  }

  const isAction = operation !== "edit";
  const title = isAction ? operation === "deactivate" ? "Dar de baja alumno" : operation === "duplicate" ? "Marcar movimiento duplicado" : `Cancelar ${titles[kind]?.toLowerCase() ?? "registro"}` : titles[kind] ?? "Editar registro";

  return <div className="modalLayer" role="dialog" aria-modal="true">
    <button className="backdrop" onClick={close} aria-label="Cerrar" />
    <form className="modal correctionModal" onSubmit={save}>
      <div className="modalHead"><div><p className="eyebrow">CORRECCIÓN OPERATIVA</p><h2>{title}</h2></div><button type="button" className="iconButton" onClick={close}><X size={20} /></button></div>
      {isAction ? <>
        <p className="formNote">El registro no se borrará físicamente. Se conservará en el historial y dejará de contar en los saldos operativos.</p>
        <label>Motivo<textarea required value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Explica por qué se corrige o cancela" /></label>
      </> : loading ? <p className="formNote">Cargando datos…</p> : <>
        {kind === "student" && <><div className="formRow"><label>Matrícula<input required value={enrollment} onChange={(event) => setEnrollment(event.target.value)} /></label><label>Grado<input required value={grade} onChange={(event) => setGrade(event.target.value)} /></label></div><div className="formRow"><label>Nombre<input required value={firstName} onChange={(event) => setFirstName(event.target.value)} /></label><label>Apellidos<input required value={lastName} onChange={(event) => setLastName(event.target.value)} /></label></div><div className="formRow"><label>Nivel<input value={level} onChange={(event) => setLevel(event.target.value)} /></label><label>Tutor<input value={tutorName} onChange={(event) => setTutorName(event.target.value)} /></label></div><label>Teléfono del tutor<input value={tutorPhone} onChange={(event) => setTutorPhone(event.target.value)} /></label></>}
        {kind === "charge" && <div className="formRow"><label>Vencimiento<input required type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label><label>Importe total<input required type="number" min=".01" step=".01" value={amount} onChange={(event) => setAmount(event.target.value)} /></label></div>}
        {kind === "income" && <><div className="formRow"><label>Fecha<input required type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label><label>Importe<input required type="number" min=".01" step=".01" value={amount} onChange={(event) => setAmount(event.target.value)} /></label></div><div className="formRow"><label>Forma de pago<select value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value)}><option value="efectivo">Efectivo</option><option value="transferencia">Transferencia</option><option value="tarjeta">Tarjeta</option><option value="otro">Otro</option></select></label><label>Referencia bancaria<input value={bankReference} onChange={(event) => setBankReference(event.target.value)} /></label></div></>}
        {kind === "expense" && <><div className="formRow"><label>Fecha<input required type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label><label>Proveedor<input value={supplier} onChange={(event) => setSupplier(event.target.value)} /></label></div><label>Descripción<input required value={description} onChange={(event) => setDescription(event.target.value)} /></label><div className="formRow"><label>Subtotal<input required type="number" min="0" step=".01" value={amount} onChange={(event) => setAmount(event.target.value)} /></label><label>Impuesto<input required type="number" min="0" step=".01" value={tax} onChange={(event) => setTax(event.target.value)} /></label></div><div className="formRow"><label>Cuenta<select required value={accountId} onChange={(event) => setAccountId(event.target.value)}>{accounts.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>Partida<select required value={categoryId} onChange={(event) => setCategoryId(event.target.value)}>{categories.map((item) => <option key={item.id} value={item.id}>{item.name} · {item.type}</option>)}</select></label></div><label>Forma de pago<select value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value)}><option value="efectivo">Efectivo</option><option value="transferencia">Transferencia</option><option value="tarjeta">Tarjeta</option><option value="otro">Otro</option></select></label></>}
        {kind === "transfer" && <><div className="formRow"><label>Fecha<input required type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label><label>Importe<input required type="number" min=".01" step=".01" value={amount} onChange={(event) => setAmount(event.target.value)} /></label></div><label>Motivo<input required value={description} onChange={(event) => setDescription(event.target.value)} /></label><div className="formRow"><label>Cuenta origen<select required value={accountId} onChange={(event) => setAccountId(event.target.value)}>{accounts.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>Cuenta destino<select required value={destinationAccountId} onChange={(event) => setDestinationAccountId(event.target.value)}>{accounts.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label></div></>}
        {kind === "bank" && <><div className="formRow"><label>Fecha banco<input required type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label><label>Importe<input required type="number" step=".01" value={amount} onChange={(event) => setAmount(event.target.value)} /></label></div><label>Descripción<input required value={description} onChange={(event) => setDescription(event.target.value)} /></label><div className="formRow"><label>Referencia<input value={bankReference} onChange={(event) => setBankReference(event.target.value)} /></label><label>Estado<select value={status} onChange={(event) => setStatus(event.target.value)}><option value="pendiente">Pendiente</option><option value="no_identificado">No identificado</option><option value="conciliado">Conciliado</option><option value="duplicado">Duplicado</option></select></label></div></>}
      </>}
      {message && <p className="formError">{message}</p>}
      <div className="modalActions"><button type="button" className="secondary" onClick={close}>Cerrar</button><button className={isAction ? "primary dangerButton" : "primary"} disabled={busy || loading}>{busy ? "Guardando…" : isAction ? "Confirmar acción" : "Guardar cambios"}</button></div>
    </form>
  </div>;
}
