"use client";

import { Download, FileSpreadsheet, FileText } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type ReportKind = "cobranza" | "ingresos" | "egresos" | "resultados";
type ExportFormat = "pdf" | "csv" | "xlsx";
type ReportTable = { headers: string[]; rows: (string | number)[][] };

const money = new Intl.NumberFormat("es-MX", { style: "currency", currency: "MXN", maximumFractionDigits: 2 });

function paymentLabel(status: string) {
  if (status === "pagado") return "Pagado";
  if (status === "pagado_retraso") return "Pagó con retardo";
  return "No ha pagado";
}

function downloadBlob(content: BlobPart, type: string, filename: string) {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

function csvCell(value: string | number) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

export function ReportCenter() {
  const supabase = useMemo(() => createClient(), []);
  const [kind, setKind] = useState<ReportKind>("cobranza");
  const [format, setFormat] = useState<ExportFormat>("pdf");
  const [grade, setGrade] = useState("todos");
  const [paymentStatus, setPaymentStatus] = useState("todos");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [loading, setLoading] = useState(true);
  const [exporting, setExporting] = useState(false);
  const [error, setError] = useState("");
  const [statuses, setStatuses] = useState<Record<string, unknown>[]>([]);
  const [incomes, setIncomes] = useState<Record<string, unknown>[]>([]);
  const [expenses, setExpenses] = useState<Record<string, unknown>[]>([]);
  const [students, setStudents] = useState<Record<string, unknown>[]>([]);

  useEffect(() => {
    async function load() {
      setLoading(true);
      setError("");
      const [statusResult, incomeResult, expenseResult, studentResult] = await Promise.all([
        supabase.from("student_payment_status").select("student_id,enrollment,first_name,last_name,grade,concept,net_amount,late_fee_amount,paid_amount,balance,due_on,paid_on,payment_status").order("enrollment"),
        supabase.from("incomes").select("id,paid_on,student_id,payment_method,reference,amount,status").eq("status", "confirmado").order("paid_on", { ascending: false }),
        supabase.from("expenses").select("id,spent_on,supplier,description,payment_method,total,status").eq("status", "confirmado").order("spent_on", { ascending: false }),
        supabase.from("students").select("id,enrollment,first_name,last_name,grade"),
      ]);
      const firstError = statusResult.error || incomeResult.error || expenseResult.error || studentResult.error;
      if (firstError) setError(firstError.message);
      setStatuses((statusResult.data ?? []) as Record<string, unknown>[]);
      setIncomes((incomeResult.data ?? []) as Record<string, unknown>[]);
      setExpenses((expenseResult.data ?? []) as Record<string, unknown>[]);
      setStudents((studentResult.data ?? []) as Record<string, unknown>[]);
      setLoading(false);
    }
    load();
    window.addEventListener("cei:data-changed", load);
    return () => window.removeEventListener("cei:data-changed", load);
  }, [supabase]);

  const grades = useMemo(() => Array.from(new Set(statuses.map((row) => String(row.grade ?? "")).filter(Boolean))).sort(), [statuses]);
  const studentMap = useMemo(() => new Map(students.map((student) => [String(student.id), student])), [students]);

  const table = useMemo<ReportTable>(() => {
    const inRange = (value: unknown) => {
      const date = String(value ?? "");
      return (!from || date >= from) && (!to || date <= to);
    };
    if (kind === "cobranza") {
      return {
        headers: ["Matrícula", "Alumno", "Salón", "Concepto", "Vencimiento", "Cargo", "Recargo", "Pagado", "Saldo", "Estado"],
        rows: statuses.filter((row) => (grade === "todos" || row.grade === grade) && (paymentStatus === "todos" || row.payment_status === paymentStatus) && inRange(row.due_on)).map((row) => [
          String(row.enrollment ?? ""), `${row.first_name} ${row.last_name}`, String(row.grade ?? ""), String(row.concept ?? "Sin cargo"), String(row.due_on ?? ""),
          Number(row.net_amount ?? 0), Number(row.late_fee_amount ?? 0), Number(row.paid_amount ?? 0), Number(row.balance ?? 0), paymentLabel(String(row.payment_status)),
        ]),
      };
    }
    if (kind === "ingresos") {
      return {
        headers: ["Folio", "Fecha", "Matrícula", "Alumno", "Forma", "Referencia", "Importe"],
        rows: incomes.filter((row) => inRange(row.paid_on) && (grade === "todos" || studentMap.get(String(row.student_id))?.grade === grade)).map((row) => {
          const student = studentMap.get(String(row.student_id));
          return [`ING-${String(row.id).slice(0, 6).toUpperCase()}`, String(row.paid_on ?? ""), String(student?.enrollment ?? ""), student ? `${student.first_name} ${student.last_name}` : "Sin identificar", String(row.payment_method ?? ""), String(row.reference ?? ""), Number(row.amount ?? 0)];
        }),
      };
    }
    if (kind === "egresos") {
      return {
        headers: ["Folio", "Fecha", "Proveedor", "Descripción", "Forma", "Total"],
        rows: expenses.filter((row) => inRange(row.spent_on)).map((row) => [`EGR-${String(row.id).slice(0, 6).toUpperCase()}`, String(row.spent_on ?? ""), String(row.supplier ?? ""), String(row.description ?? ""), String(row.payment_method ?? ""), Number(row.total ?? 0)]),
      };
    }
    const filteredIncome = incomes.filter((row) => inRange(row.paid_on));
    const filteredExpenses = expenses.filter((row) => inRange(row.spent_on));
    const incomeTotal = filteredIncome.reduce((sum, row) => sum + Number(row.amount ?? 0), 0);
    const expenseTotal = filteredExpenses.reduce((sum, row) => sum + Number(row.total ?? 0), 0);
    return { headers: ["Concepto", "Registros", "Importe"], rows: [["Ingresos", filteredIncome.length, incomeTotal], ["Egresos", filteredExpenses.length, expenseTotal], ["Resultado", "", incomeTotal - expenseTotal]] };
  }, [expenses, from, grade, incomes, kind, paymentStatus, statuses, studentMap, to]);

  const reportName = { cobranza: "Cobranza por alumno", ingresos: "Ingresos", egresos: "Egresos", resultados: "Estado de resultados" }[kind];
  const fileBase = `reporte-${kind}-${new Date().toISOString().slice(0, 10)}`;

  async function exportReport() {
    if (!table.rows.length) return;
    setExporting(true);
    setError("");
    try {
      if (format === "csv") {
        const csv = [table.headers, ...table.rows].map((row) => row.map(csvCell).join(",")).join("\r\n");
        downloadBlob(`\uFEFF${csv}`, "text/csv;charset=utf-8", `${fileBase}.csv`);
      } else if (format === "xlsx") {
        const ExcelJS = await import("exceljs");
        const workbook = new ExcelJS.Workbook();
        const sheet = workbook.addWorksheet("Reporte");
        sheet.addRow([reportName]);
        sheet.mergeCells(1, 1, 1, table.headers.length);
        sheet.getCell("A1").font = { size: 16, bold: true, color: { argb: "FFFFFFFF" } };
        sheet.getCell("A1").fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF173F35" } };
        sheet.addRow([`Generado: ${new Intl.DateTimeFormat("es-MX", { dateStyle: "long" }).format(new Date())}`]);
        sheet.mergeCells(2, 1, 2, table.headers.length);
        const header = sheet.addRow(table.headers);
        header.font = { bold: true, color: { argb: "FFFFFFFF" } };
        header.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF2E6B58" } };
        table.rows.forEach((row) => sheet.addRow(row));
        sheet.views = [{ state: "frozen", ySplit: 3 }];
        sheet.autoFilter = { from: { row: 3, column: 1 }, to: { row: 3 + table.rows.length, column: table.headers.length } };
        sheet.columns.forEach((column, index) => { column.width = Math.min(38, Math.max(12, table.headers[index]?.length + 3 || 12)); });
        sheet.eachRow((row, rowNumber) => { if (rowNumber > 3 && rowNumber % 2 === 0) row.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF2F6F4" } }; });
        const buffer = await workbook.xlsx.writeBuffer();
        downloadBlob(buffer, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", `${fileBase}.xlsx`);
      } else {
        const [{ jsPDF }, autoTableModule] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
        const document = new jsPDF({ orientation: table.headers.length > 7 ? "landscape" : "portrait" });
        document.setFontSize(17);
        document.setTextColor(23, 63, 53);
        document.text(reportName, 14, 17);
        document.setFontSize(9);
        document.setTextColor(90, 105, 100);
        document.text(`Generado: ${new Intl.DateTimeFormat("es-MX", { dateStyle: "long" }).format(new Date())} · ${table.rows.length} registros`, 14, 24);
        autoTableModule.default(document, { head: [table.headers], body: table.rows.map((row) => row.map((cell) => typeof cell === "number" ? money.format(cell) : cell)), startY: 29, styles: { fontSize: 7, cellPadding: 2 }, headStyles: { fillColor: [46, 107, 88] }, alternateRowStyles: { fillColor: [242, 246, 244] } });
        document.save(`${fileBase}.pdf`);
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "No se pudo generar el archivo.");
    } finally {
      setExporting(false);
    }
  }

  return <section className="modulePage reportPage">
    <div className="moduleHead"><div><p className="eyebrow">CICLO ACTIVO</p><h1>Reportes</h1><p>Filtra la información y descarga el resultado listo para compartir.</p></div></div>
    <div className="panel reportBuilder">
      <div className="reportFilters">
        <label><span>Reporte</span><select value={kind} onChange={(event) => setKind(event.target.value as ReportKind)}><option value="cobranza">Cobranza por alumno</option><option value="ingresos">Ingresos</option><option value="egresos">Egresos</option><option value="resultados">Estado de resultados</option></select></label>
        {(kind === "cobranza" || kind === "ingresos") && <label><span>Salón</span><select value={grade} onChange={(event) => setGrade(event.target.value)}><option value="todos">Todos</option>{grades.map((item) => <option key={item}>{item}</option>)}</select></label>}
        {kind === "cobranza" && <label><span>Estado</span><select value={paymentStatus} onChange={(event) => setPaymentStatus(event.target.value)}><option value="todos">Todos</option><option value="pagado">Pagado</option><option value="pagado_retraso">Pagó con retardo</option><option value="no_pagado">No ha pagado</option></select></label>}
        <label><span>Desde</span><input type="date" value={from} onChange={(event) => setFrom(event.target.value)}/></label>
        <label><span>Hasta</span><input type="date" value={to} onChange={(event) => setTo(event.target.value)}/></label>
      </div>
      <div className="reportExportBar"><div><strong>{reportName}</strong><span>{loading ? "Cargando…" : `${table.rows.length} registros listos`}</span></div><div className="formatControl"><button className={format === "pdf" ? "active" : ""} onClick={() => setFormat("pdf")}><FileText size={16}/>PDF</button><button className={format === "csv" ? "active" : ""} onClick={() => setFormat("csv")}><Download size={16}/>CSV</button><button className={format === "xlsx" ? "active" : ""} onClick={() => setFormat("xlsx")}><FileSpreadsheet size={16}/>Excel</button></div><button className="primary" disabled={loading || exporting || !table.rows.length} onClick={exportReport}><Download size={17}/>{exporting ? "Generando…" : `Descargar ${format.toUpperCase()}`}</button></div>
      {error && <div className="formError">{error}</div>}
    </div>
    <div className="panel moduleTable reportPreview"><div className="tableWrap"><table><thead><tr>{table.headers.map((header) => <th key={header}>{header}</th>)}</tr></thead><tbody>{table.rows.slice(0, 50).map((row, index) => <tr key={index}>{row.map((cell, cellIndex) => <td key={cellIndex} data-label={table.headers[cellIndex]}>{typeof cell === "number" && (table.headers[cellIndex].includes("Importe") || ["Cargo", "Recargo", "Pagado", "Saldo", "Total"].includes(table.headers[cellIndex])) ? money.format(cell) : cell}</td>)}</tr>)}</tbody></table>{!loading && !table.rows.length && <div className="empty">No hay datos que coincidan con los filtros.</div>}</div><div className="panelFooter"><span>Vista previa de {Math.min(table.rows.length, 50)} de {table.rows.length} registros</span></div></div>
  </section>;
}
