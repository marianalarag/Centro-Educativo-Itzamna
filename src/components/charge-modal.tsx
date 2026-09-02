"use client";

import { AlertTriangle, CheckCircle2, Clock3, UserPlus, Users, X } from "lucide-react";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Student = { id: string; enrollment: string; first_name: string; last_name: string; level: string; grade: string };
type Concept = { id: string; name: string; base_amount: number };
type Fee = { concept_id: string; level: string; grade: string; amount: number };
type SaveResult = { base_amount: number; late_fee_amount: number; total: number; payment_status: string };

const money = new Intl.NumberFormat("es-MX", { style: "currency", currency: "MXN" });
const today = () => new Date().toISOString().slice(0, 10);

export function ChargeModal({ close }: { close: () => void }) {
  const supabase = useMemo(() => createClient(), []);
  const [students, setStudents] = useState<Student[]>([]);
  const [concepts, setConcepts] = useState<Concept[]>([]);
  const [fees, setFees] = useState<Fee[]>([]);
  const [studentMode, setStudentMode] = useState<"existing" | "new">("existing");
  const [paymentMode, setPaymentMode] = useState<"paid" | "pending">("paid");
  const [studentId, setStudentId] = useState("");
  const [conceptId, setConceptId] = useState("");
  const [dueOn, setDueOn] = useState(today());
  const [paidOn, setPaidOn] = useState(today());
  const [lateRate, setLateRate] = useState(10);
  const [method, setMethod] = useState("efectivo");
  const [newStudent, setNewStudent] = useState({ enrollment: "", firstName: "", lastName: "", level: "Primaria", grade: "", tutor: "", phone: "" });
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");

  const selectedStudent = students.find((student) => student.id === studentId);
  const selectedConcept = concepts.find((concept) => concept.id === conceptId);
  const selectedLevel = studentMode === "existing" ? selectedStudent?.level : newStudent.level;
  const selectedGrade = studentMode === "existing" ? selectedStudent?.grade : newStudent.grade;
  const selectedFee = fees.find((item) => item.concept_id === conceptId && item.level === selectedLevel && item.grade === selectedGrade);
  const baseAmount = Number(selectedFee?.amount ?? selectedConcept?.base_amount ?? 0);
  const isLate = paymentMode === "paid" && !!paidOn && !!dueOn && paidOn > dueOn;
  const lateFee = isLate ? Math.round(baseAmount * lateRate) / 100 : 0;
  const total = baseAmount + lateFee;

  useEffect(() => {
    async function loadCatalogs() {
      const [{ data: studentRows, error: studentError }, { data: conceptRows, error: conceptError }, { data: feeRows }] = await Promise.all([
        supabase.from("students").select("id,enrollment,first_name,last_name,level,grade").eq("active", true).order("first_name"),
        supabase.from("payment_concepts").select("id,name,base_amount").eq("active", true).order("name"),
        supabase.from("fees").select("concept_id,level,grade,amount"),
      ]);
      if (studentError || conceptError) setMessage(studentError?.message ?? conceptError?.message ?? "No se pudieron cargar los catalogos.");
      const nextStudents = (studentRows ?? []) as Student[];
      const nextConcepts = (conceptRows ?? []) as Concept[];
      setStudents(nextStudents);
      setConcepts(nextConcepts);
      setFees((feeRows ?? []) as Fee[]);
      setStudentId(nextStudents[0]?.id ?? "");
      setConceptId(nextConcepts.find((item) => item.name.toLowerCase() === "colegiatura")?.id ?? nextConcepts[0]?.id ?? "");
      setLoading(false);
    }
    loadCatalogs();
  }, [supabase]);

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      if (studentMode === "existing" && !studentId) throw new Error("Selecciona un alumno.");
      if (!conceptId || baseAmount <= 0) throw new Error("Selecciona un concepto con precio configurado.");
      const { data, error } = await supabase.rpc("create_student_charge", {
        p_student_id: studentMode === "existing" ? studentId : null,
        p_enrollment: studentMode === "new" ? newStudent.enrollment : null,
        p_first_name: studentMode === "new" ? newStudent.firstName : null,
        p_last_name: studentMode === "new" ? newStudent.lastName : null,
        p_level: studentMode === "new" ? newStudent.level : null,
        p_grade: studentMode === "new" ? newStudent.grade : null,
        p_tutor_name: studentMode === "new" ? newStudent.tutor : null,
        p_tutor_phone: studentMode === "new" ? newStudent.phone : null,
        p_concept_id: conceptId,
        p_due_on: dueOn,
        p_paid_on: paymentMode === "paid" ? paidOn : null,
        p_base_amount: baseAmount,
        p_late_fee_rate: lateRate,
        p_payment_method: method,
      });
      if (error) throw error;
      const result = data as SaveResult;
      window.dispatchEvent(new Event("cei:data-changed"));
      setMessage(result.payment_status === "no_pagado" ? "Adeudo guardado. El alumno aparecera como no pagado." : `Pago guardado por ${money.format(result.total)}.`);
      window.setTimeout(close, 900);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo guardar el cobro.");
    } finally {
      setBusy(false);
    }
  }

  return <div className="modalLayer" role="dialog" aria-modal="true" aria-label="Nuevo cobro">
    <button className="backdrop" onClick={close} aria-label="Cerrar" />
    <form className="modal chargeModal" onSubmit={save}>
      <div className="modalHead"><div><p className="eyebrow">CAPTURA INTEGRAL</p><h2>Nuevo cobro</h2></div><button type="button" className="iconButton" onClick={close} aria-label="Cerrar"><X size={20} /></button></div>

      <div className="segmented" aria-label="Tipo de alumno">
        <button type="button" className={studentMode === "existing" ? "active" : ""} onClick={() => setStudentMode("existing")}><Users size={16}/>Alumno existente</button>
        <button type="button" className={studentMode === "new" ? "active" : ""} onClick={() => setStudentMode("new")}><UserPlus size={16}/>Alumno nuevo</button>
      </div>

      {studentMode === "existing" ? <label>Alumno<select required value={studentId} onChange={(event) => setStudentId(event.target.value)} disabled={loading}>
        {!students.length && <option value="">No hay alumnos disponibles</option>}
        {students.map((student) => <option key={student.id} value={student.id}>{student.enrollment} - {student.first_name} {student.last_name} - {student.grade}</option>)}
      </select></label> : <div className="newStudentFields">
        <div className="formRow"><label>Matricula<input required value={newStudent.enrollment} onChange={(event) => setNewStudent({ ...newStudent, enrollment: event.target.value })} placeholder="CEI-0311" /></label><label>Nivel<select value={newStudent.level} onChange={(event) => setNewStudent({ ...newStudent, level: event.target.value })}><option>Primaria</option><option>Preescolar</option><option>Secundaria</option></select></label></div>
        <div className="formRow"><label>Nombre<input required value={newStudent.firstName} onChange={(event) => setNewStudent({ ...newStudent, firstName: event.target.value })} /></label><label>Apellidos<input required value={newStudent.lastName} onChange={(event) => setNewStudent({ ...newStudent, lastName: event.target.value })} /></label></div>
        <div className="formRow"><label>Grado<input required value={newStudent.grade} onChange={(event) => setNewStudent({ ...newStudent, grade: event.target.value })} placeholder="4 Primaria" /></label><label>Tutor<input value={newStudent.tutor} onChange={(event) => setNewStudent({ ...newStudent, tutor: event.target.value })} /></label></div>
        <label>Telefono del tutor<input type="tel" value={newStudent.phone} onChange={(event) => setNewStudent({ ...newStudent, phone: event.target.value })} /></label>
      </div>}

      <div className="formRow"><label>Concepto<select required value={conceptId} onChange={(event) => setConceptId(event.target.value)}>{concepts.map((concept) => <option key={concept.id} value={concept.id}>{concept.name}</option>)}</select></label><label>Precio base<input readOnly value={baseAmount ? money.format(baseAmount) : "Sin tarifa"} /></label></div>
      <div className="formRow"><label>Fecha de vencimiento<input required type="date" value={dueOn} onChange={(event) => setDueOn(event.target.value)} /></label><label>Recargo por atraso (%)<input required type="number" min="0" max="100" step=".5" value={lateRate} onChange={(event) => setLateRate(Number(event.target.value))} /></label></div>

      <div className="segmented paymentChoice" aria-label="Estado del pago">
        <button type="button" className={paymentMode === "paid" ? "active" : ""} onClick={() => setPaymentMode("paid")}><CheckCircle2 size={16}/>Registrar pago</button>
        <button type="button" className={paymentMode === "pending" ? "active danger" : ""} onClick={() => setPaymentMode("pending")}><AlertTriangle size={16}/>Dejar pendiente</button>
      </div>

      {paymentMode === "paid" && <div className="formRow"><label>Fecha de pago<input required type="date" value={paidOn} onChange={(event) => setPaidOn(event.target.value)} /></label><label>Forma de pago<select value={method} onChange={(event) => setMethod(event.target.value)}><option value="efectivo">Efectivo</option><option value="transferencia">Transferencia</option><option value="tarjeta">Tarjeta</option><option value="otro">Otro</option></select></label></div>}

      <div className={`chargeSummary ${paymentMode === "pending" ? "pending" : isLate ? "late" : "paid"}`}>
        <div><span>Precio base</span><b>{money.format(baseAmount)}</b></div>
        <div><span>{isLate ? `Recargo (${lateRate}%)` : "Recargo"}</span><b>{money.format(lateFee)}</b></div>
        <strong><span>{paymentMode === "pending" ? "Saldo pendiente" : "Total a cobrar"}</span>{money.format(total)}</strong>
        <p>{paymentMode === "pending" ? <><AlertTriangle size={15}/>Se guardara como NO HA PAGADO y sera visible en el dashboard.</> : isLate ? <><Clock3 size={15}/>Pago posterior al vencimiento. Se aplicara el recargo.</> : <><CheckCircle2 size={15}/>Pago dentro de la fecha establecida.</>}</p>
      </div>

      {message && <p className={message.startsWith("Pago") || message.startsWith("Adeudo") ? "formSuccess" : "formError"}>{message}</p>}
      <div className="modalActions"><button type="button" className="secondary" onClick={close}>Cancelar</button><button className="primary" disabled={busy || loading}>{busy ? "Guardando..." : paymentMode === "pending" ? "Guardar adeudo" : `Cobrar ${money.format(total)}`}</button></div>
    </form>
  </div>;
}
