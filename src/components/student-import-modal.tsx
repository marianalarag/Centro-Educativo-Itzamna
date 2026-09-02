"use client";

import { Download, FileSpreadsheet, Upload, X } from "lucide-react";
import { ChangeEvent, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { demoStudents, parseStudentFile, StudentImportRow } from "@/lib/student-import";

function rowStatus(row: StudentImportRow) {
  if (!row.paid_on) return { label: "No ha pagado", tone: "unpaid" };
  if (row.due_on && row.paid_on > row.due_on) return { label: "Pagó con retardo", tone: "late" };
  return { label: "Pagado", tone: "paid" };
}

function expectedTotal(row: StudentImportRow) {
  return row.paid_on && row.due_on && row.paid_on > row.due_on
    ? row.amount * (1 + row.late_fee_rate / 100)
    : row.amount;
}

export function StudentImportModal({
  close,
  role,
}: {
  close: () => void;
  role: string;
}) {
  const supabase = useMemo(() => createClient(), []);
  const inputRef = useRef<HTMLInputElement>(null);
  const [rows, setRows] = useState<StudentImportRow[]>([]);
  const [errors, setErrors] = useState<string[]>([]);
  const [fileName, setFileName] = useState("");
  const [demoMode, setDemoMode] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  async function selectFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setBusy(true);
    setMessage("");
    try {
      const parsed = await parseStudentFile(file);
      setRows(parsed.rows);
      setErrors(parsed.errors);
      setFileName(file.name);
      setDemoMode(false);
    } catch {
      setRows([]);
      setErrors(["No se pudo leer el archivo. Verifica que no esté dañado o protegido con contraseña."]);
      setFileName(file.name);
    } finally {
      setBusy(false);
    }
  }

  function useDemo() {
    setRows(demoStudents);
    setErrors([]);
    setFileName("Prueba financiera de 10 alumnos");
    setDemoMode(true);
    setMessage("");
  }

  async function importRows() {
    if (!rows.length || errors.length) return;
    setBusy(true);
    setMessage("");
    const { data, error } = demoMode
      ? await supabase.rpc("load_financial_demo")
      : await supabase.rpc("import_student_finances", { p_rows: rows });

    if (error) {
      setMessage(error.message);
      setBusy(false);
      return;
    }

    const result = data as { students?: number; payments?: number; expenses?: number; late_fees?: number } | null;
    const lateFees = Number(result?.late_fees ?? 0);
    setMessage(
      `Listo: ${result?.students ?? rows.length} alumnos, ${result?.payments ?? 0} ingresos` +
      (demoMode ? ` y ${result?.expenses ?? 0} egresos nuevos.` : lateFees > 0 ? ` y ${lateFees.toLocaleString("es-MX", { style: "currency", currency: "MXN" })} en recargos.` : "."),
    );
    window.dispatchEvent(new Event("cei:data-changed"));
    setBusy(false);
  }

  return <div className="modalLayer" role="dialog" aria-modal="true" aria-label="Importar alumnos">
    <button className="backdrop" onClick={close} aria-label="Cerrar" />
    <section className="modal importModal">
      <div className="modalHead">
        <div><p className="eyebrow">IMPORTACIÓN</p><h2>Alumnos desde CSV o Excel</h2></div>
        <button type="button" className="iconButton" onClick={close} aria-label="Cerrar"><X size={20} /></button>
      </div>

      <div className="importActions">
        <button className="uploadDrop" type="button" onClick={() => inputRef.current?.click()} disabled={busy}>
          <Upload size={22} />
          <span><strong>Seleccionar archivo</strong><small>.csv o .xlsx · máximo 500 filas</small></span>
        </button>
        <input ref={inputRef} className="srOnly" type="file" accept=".csv,.xlsx" onChange={selectFile} />
        <a className="secondary templateLink" href="/plantilla-alumnos.csv" download>
          <Download size={17} /> Plantilla
        </a>
        {role === "direccion" && <button className="secondary" type="button" onClick={useDemo} disabled={busy}>
          <FileSpreadsheet size={17} /> Usar prueba de 10
        </button>}
      </div>

      {fileName && <div className="selectedFile"><FileSpreadsheet size={17} /><span>{fileName}</span><strong>{rows.length} válidos</strong></div>}
      {!!errors.length && <div className="importErrors" role="alert">
        {errors.slice(0, 8).map((error) => <p key={error}>{error}</p>)}
        {errors.length > 8 && <p>Hay {errors.length - 8} errores adicionales.</p>}
      </div>}

      {!!rows.length && <div className="importPreview">
        <table>
          <thead><tr><th>Matrícula</th><th>Alumno</th><th>Grado</th><th>Base</th><th>Total esperado</th><th>Estado esperado</th></tr></thead>
          <tbody>{rows.slice(0, 10).map((row) => {
            const status = rowStatus(row);
            return <tr key={row.enrollment}>
              <td>{row.enrollment}</td>
              <td className="person">{row.first_name} {row.last_name}</td>
              <td>{row.grade}</td>
              <td>{row.amount ? row.amount.toLocaleString("es-MX", { style: "currency", currency: "MXN" }) : "Sin cargo"}</td>
              <td>{expectedTotal(row).toLocaleString("es-MX", { style: "currency", currency: "MXN" })}</td>
              <td><span className={`paymentBadge ${status.tone}`}>{status.label}</span></td>
            </tr>;
          })}</tbody>
        </table>
      </div>}

      {message && <p className={message.startsWith("Listo") ? "formSuccess" : "formError"}>{message}</p>}
      <div className="modalActions">
        <button type="button" className="secondary" onClick={close}>Cerrar</button>
        <button type="button" className="primary" onClick={importRows} disabled={busy || !rows.length || !!errors.length}>
          {busy ? "Procesando…" : demoMode ? "Cargar prueba financiera" : `Importar ${rows.length || ""} alumnos`}
        </button>
      </div>
    </section>
  </div>;
}
