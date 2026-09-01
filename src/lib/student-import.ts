import Papa from "papaparse";
import { readSheet } from "read-excel-file/browser";

export type StudentImportRow = {
  enrollment: string;
  first_name: string;
  last_name: string;
  level: string;
  grade: string;
  tutor_name: string | null;
  tutor_phone: string | null;
  tutor_email: string | null;
  concept: string;
  amount: number;
  due_on: string;
  paid_on: string | null;
  payment_method: "efectivo" | "transferencia" | "tarjeta" | "otro";
};

export type ParsedStudentFile = {
  rows: StudentImportRow[];
  errors: string[];
};

type Cell = string | number | boolean | Date | null | undefined;

const aliases: Record<string, string[]> = {
  enrollment: ["matricula", "matrícula", "enrollment", "clave"],
  full_name: ["nombre", "nombre completo", "alumno", "estudiante"],
  first_name: ["nombres", "primer nombre"],
  last_name: ["apellidos", "apellido", "apellido(s)"],
  level: ["nivel", "seccion", "sección"],
  grade: ["grado", "grupo", "grado y grupo"],
  tutor_name: ["tutor", "nombre tutor", "responsable"],
  tutor_phone: ["telefono", "teléfono", "telefono tutor", "celular"],
  tutor_email: ["correo", "email", "correo tutor"],
  concept: ["concepto", "concepto de pago"],
  amount: ["monto", "importe", "cargo", "colegiatura"],
  due_on: ["fecha limite", "fecha límite", "vencimiento", "fecha vencimiento"],
  paid_on: ["fecha pago", "fecha de pago", "pagado el"],
  payment_method: ["forma de pago", "metodo de pago", "método de pago"],
};

function normalize(value: Cell) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLocaleLowerCase("es");
}

function text(value: Cell) {
  return String(value ?? "").trim();
}

function toIsoDate(value: Cell) {
  if (value instanceof Date && !Number.isNaN(value.valueOf())) {
    return value.toISOString().slice(0, 10);
  }
  if (typeof value === "number" && value > 20_000 && value < 80_000) {
    const excelEpoch = Date.UTC(1899, 11, 30);
    return new Date(excelEpoch + value * 86_400_000).toISOString().slice(0, 10);
  }
  const raw = text(value);
  if (!raw) return "";
  const iso = raw.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$/);
  if (iso) return `${iso[1]}-${iso[2].padStart(2, "0")}-${iso[3].padStart(2, "0")}`;
  const local = raw.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$/);
  if (local) return `${local[3]}-${local[2].padStart(2, "0")}-${local[1].padStart(2, "0")}`;
  return "";
}

function amountFrom(value: Cell) {
  if (typeof value === "number") return value;
  const raw = text(value).replace(/[$\s]/g, "");
  const normalized = raw.includes(",") && !raw.includes(".")
    ? raw.replace(",", ".")
    : raw.replace(/,/g, "");
  return Number(normalized);
}

function paymentMethod(value: Cell): StudentImportRow["payment_method"] {
  const method = normalize(value);
  if (method.includes("trans")) return "transferencia";
  if (method.includes("tarj")) return "tarjeta";
  if (method.includes("efec") || !method) return "efectivo";
  return "otro";
}

function splitName(fullName: string) {
  const parts = fullName.split(/\s+/).filter(Boolean);
  if (parts.length < 2) return { firstName: parts[0] ?? "", lastName: "Pendiente" };
  if (parts.length === 2) return { firstName: parts[0], lastName: parts[1] };
  const surnameCount = parts.length >= 4 ? 2 : 1;
  return {
    firstName: parts.slice(0, -surnameCount).join(" "),
    lastName: parts.slice(-surnameCount).join(" "),
  };
}

function rowsFromMatrix(matrix: Cell[][]): ParsedStudentFile {
  const errors: string[] = [];
  const rawHeaders = matrix[0] ?? [];
  const headers = rawHeaders.map(normalize);
  const indexes = Object.fromEntries(Object.entries(aliases).map(([key, names]) => [
    key,
    headers.findIndex((header) => names.some((name) => normalize(name) === header)),
  ])) as Record<string, number>;

  if (indexes.enrollment < 0) errors.push("Falta la columna Matrícula.");
  if (indexes.full_name < 0 && indexes.first_name < 0) errors.push("Falta la columna Nombre o Nombres.");
  if (indexes.grade < 0) errors.push("Falta la columna Grado.");
  if (errors.length) return { rows: [], errors };

  const get = (row: Cell[], key: string) => indexes[key] >= 0 ? row[indexes[key]] : null;
  const rows: StudentImportRow[] = [];

  matrix.slice(1).forEach((rawRow, index) => {
    const rowNumber = index + 2;
    if (rawRow.every((cell) => !text(cell))) return;
    const fullName = text(get(rawRow, "full_name"));
    const split = splitName(fullName);
    const firstName = text(get(rawRow, "first_name")) || split.firstName;
    const lastName = text(get(rawRow, "last_name")) || split.lastName;
    const enrollment = text(get(rawRow, "enrollment"));
    const grade = text(get(rawRow, "grade"));
    const amount = amountFrom(get(rawRow, "amount"));
    const dueOn = toIsoDate(get(rawRow, "due_on"));
    const paidRaw = get(rawRow, "paid_on");
    const paidOn = text(paidRaw) ? toIsoDate(paidRaw) : null;

    const rowErrors: string[] = [];
    if (!enrollment) rowErrors.push("matrícula vacía");
    if (!firstName) rowErrors.push("nombre vacío");
    if (!grade) rowErrors.push("grado vacío");
    if (indexes.amount >= 0 && (!Number.isFinite(amount) || amount <= 0)) rowErrors.push("monto inválido");
    if (indexes.due_on >= 0 && !dueOn) rowErrors.push("fecha límite inválida");
    if (text(paidRaw) && !paidOn) rowErrors.push("fecha de pago inválida");
    if (rowErrors.length) {
      errors.push(`Fila ${rowNumber}: ${rowErrors.join(", ")}.`);
      return;
    }

    rows.push({
      enrollment,
      first_name: firstName,
      last_name: lastName || "Pendiente",
      level: text(get(rawRow, "level")) || "Primaria",
      grade,
      tutor_name: text(get(rawRow, "tutor_name")) || null,
      tutor_phone: text(get(rawRow, "tutor_phone")) || null,
      tutor_email: text(get(rawRow, "tutor_email")) || null,
      concept: text(get(rawRow, "concept")) || "Colegiatura",
      amount: indexes.amount >= 0 ? amount : 0,
      due_on: dueOn,
      paid_on: paidOn,
      payment_method: paymentMethod(get(rawRow, "payment_method")),
    });
  });

  if (!rows.length && !errors.length) errors.push("El archivo no contiene alumnos.");
  return { rows, errors };
}

export async function parseStudentFile(file: File): Promise<ParsedStudentFile> {
  const extension = file.name.split(".").pop()?.toLocaleLowerCase();
  if (extension === "csv") {
    const result = Papa.parse<string[]>(await file.text(), { skipEmptyLines: "greedy" });
    if (result.errors.length) {
      return { rows: [], errors: result.errors.slice(0, 5).map((error) => `CSV: ${error.message}`) };
    }
    return rowsFromMatrix(result.data);
  }
  if (extension === "xlsx") {
    return rowsFromMatrix(await readSheet(file) as unknown as Cell[][]);
  }
  return { rows: [], errors: ["Usa un archivo .csv o .xlsx."] };
}

export const demoStudents: StudentImportRow[] = [
  ["CEI-0301", "Sofía", "Martínez Pech", "4° Primaria", "Laura Pech", "2026-06-10", "2026-06-08", "efectivo"],
  ["CEI-0302", "Mauricio", "Torres Solís", "3° Primaria", "Daniel Torres", "2026-06-10", "2026-06-10", "transferencia"],
  ["CEI-0303", "Ana Paula", "Díaz Cervera", "2° Primaria", "Mónica Díaz", "2026-06-10", "2026-06-05", "tarjeta"],
  ["CEI-0304", "Valentina", "López May", "5° Primaria", "Carlos López", "2026-06-10", "2026-06-09", "efectivo"],
  ["CEI-0305", "José", "Pech Chan", "1° Primaria", "María Chan", "2026-06-10", "2026-06-14", "transferencia"],
  ["CEI-0306", "Mariana", "Solís Poot", "6° Primaria", "Arturo Solís", "2026-06-10", "2026-06-18", "efectivo"],
  ["CEI-0307", "Emiliano", "Méndez Ku", "3° Primaria", "Rebeca Ku", "2026-06-10", "2026-06-12", "transferencia"],
  ["CEI-0308", "Camila", "Góngora Pool", "2° Primaria", "Iván Pool", "2026-06-10", null, "efectivo"],
  ["CEI-0309", "Leonardo", "Canto Uc", "4° Primaria", "Paola Canto", "2026-06-10", null, "efectivo"],
  ["CEI-0310", "Regina", "Sánchez Ek", "1° Primaria", "Fernando Ek", "2026-06-10", null, "efectivo"],
].map(([enrollment, firstName, lastName, grade, tutor, dueOn, paidOn, method]) => ({
  enrollment: enrollment as string,
  first_name: firstName as string,
  last_name: lastName as string,
  level: "Primaria",
  grade: grade as string,
  tutor_name: tutor as string,
  tutor_phone: null,
  tutor_email: null,
  concept: "Colegiatura",
  amount: 3250,
  due_on: dueOn as string,
  paid_on: paidOn as string | null,
  payment_method: method as StudentImportRow["payment_method"],
}));
