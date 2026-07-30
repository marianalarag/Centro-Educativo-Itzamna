"use client";

import {
  ArrowDownLeft, ArrowLeftRight, ArrowUpRight, Banknote, Bell, BookOpen,
  ChevronDown, CircleDollarSign, ClipboardList, FileText, GraduationCap,
  LogOut, Menu, Plus, Search, Users, X,
} from "lucide-react";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const nav = [
  ["Inicio", BookOpen], ["Alumnos", Users], ["Cobros", CircleDollarSign],
  ["Ingresos", ArrowDownLeft], ["Conciliación", Banknote], ["Egresos", ArrowUpRight],
  ["Nómina", ClipboardList], ["Traspasos", ArrowLeftRight], ["Becas", GraduationCap],
  ["Presupuesto", FileText], ["Reportes", BookOpen],
] as const;

const movements = [
  ["REC-00482", "30 jun, 10:42", "Sofía Martínez Pech", "Colegiatura · Mes 10", "Efectivo", 3250, "Ingreso"],
  ["TRF-00219", "30 jun, 09:18", "Mauricio Torres Solís", "Saldo colegiatura · Mes 9", "Transferencia", 50, "Ingreso"],
  ["EGR-00176", "29 jun, 13:06", "JAPAY", "Servicio de agua · Junio", "Caja PyME", -1840, "Egreso"],
  ["REC-00481", "29 jun, 12:24", "Ana Paula Díaz", "Estancia · Junio", "Efectivo", 780, "Ingreso"],
  ["TRF-00218", "29 jun, 08:51", "Depósito sin identificar", "Pendiente de asignación", "Transferencia", 3250, "Pendiente"],
] as const;

const money = new Intl.NumberFormat("es-MX", {
  style: "currency", currency: "MXN", maximumFractionDigits: 0,
});

const paths: Record<string, string> = {
  Inicio: "/", Alumnos: "/alumnos", Cobros: "/cobros", Ingresos: "/ingresos",
  Egresos: "/egresos", Nómina: "/nomina", Traspasos: "/traspasos",
  Conciliación: "/conciliacion", Becas: "/becas", Presupuesto: "/presupuesto",
  Reportes: "/reportes",
};

const namesByPath = Object.fromEntries(Object.entries(paths).map(([name, path]) => [path, name]));
type MovementRow = readonly [string, string, string, string, string, number, string];

export default function Home({ initialActive = "Inicio" }: { initialActive?: string }) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [active, setActive] = useState(initialActive);
  const [query, setQuery] = useState("");
  const [menu, setMenu] = useState(false);
  const [modal, setModal] = useState<string | null>(null);
  const [authChecking, setAuthChecking] = useState(true);
  const [dbMovements, setDbMovements] = useState<MovementRow[]>([]);
  const [summary, setSummary] = useState({ income: 0, expense: 0, pending: 0 });
  const [userName, setUserName] = useState("Personal autorizado");
  const displayMovements: readonly MovementRow[] = dbMovements.length ? dbMovements : movements;
  const visible = useMemo(() => displayMovements.filter((m) =>
    m.join(" ").toLocaleLowerCase("es").includes(query.toLocaleLowerCase("es"))), [displayMovements, query]);

  useEffect(() => {
    let mounted = true;
    supabase.auth.getUser().then(({ data }) => {
      if (mounted) {
        setAuthChecking(false);
        if (!data.user) router.replace("/login");
        else setUserName(data.user.user_metadata?.full_name || data.user.email?.split("@")[0] || "Personal autorizado");
      }
    });
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) router.replace("/login");
    });
    return () => {
      mounted = false;
      listener.subscription.unsubscribe();
    };
  }, [router, supabase]);

  useEffect(() => {
    const updateFromUrl = () => setActive(namesByPath[window.location.pathname] ?? "Inicio");
    window.addEventListener("popstate", updateFromUrl);
    return () => window.removeEventListener("popstate", updateFromUrl);
  }, []);

  useEffect(() => {
    async function loadDashboard() {
      const [{ data: incomes }, { data: expenses }, { data: students }, { data: charges }] = await Promise.all([
        supabase.from("incomes").select("id,amount,paid_on,payment_method,student_id").eq("status", "confirmado").order("paid_on", { ascending: false }).limit(10),
        supabase.from("expenses").select("id,total,spent_on,payment_method,description").eq("status", "confirmado").order("spent_on", { ascending: false }).limit(10),
        supabase.from("students").select("id,first_name,last_name"),
        supabase.from("charges").select("net_amount,paid_amount").in("status", ["pendiente", "parcial", "vencido"]),
      ]);
      const studentMap = new Map((students ?? []).map((student) => [student.id, `${student.first_name} ${student.last_name}`]));
      const incomeRows: MovementRow[] = (incomes ?? []).map((income) => [
        `ING-${income.id.slice(0, 6).toUpperCase()}`, income.paid_on, studentMap.get(income.student_id ?? "") ?? "Depósito sin identificar",
        "Ingreso registrado", income.payment_method, Number(income.amount), "Ingreso",
      ]);
      const expenseRows: MovementRow[] = (expenses ?? []).map((expense) => [
        `EGR-${expense.id.slice(0, 6).toUpperCase()}`, expense.spent_on, expense.description, "Egreso operativo",
        expense.payment_method, -Number(expense.total), "Egreso",
      ]);
      setDbMovements([...incomeRows, ...expenseRows].sort((a, b) => String(b[1]).localeCompare(String(a[1]))).slice(0, 10));
      setSummary({
        income: (incomes ?? []).reduce((sum, item) => sum + Number(item.amount), 0),
        expense: (expenses ?? []).reduce((sum, item) => sum + Number(item.total), 0),
        pending: (charges ?? []).reduce((sum, charge) => sum + Number(charge.net_amount) - Number(charge.paid_amount), 0),
      });
    }
    loadDashboard();
    window.addEventListener("cei:data-changed", loadDashboard);
    return () => window.removeEventListener("cei:data-changed", loadDashboard);
  }, [supabase]);

  const go = (name: string) => {
    setActive(name);
    setMenu(false);
    const target = paths[name] ?? "/";
    if (window.location.pathname !== target) window.history.pushState({}, "", target);
  };

  async function signOut() {
    await supabase.auth.signOut();
    router.replace("/login");
  }

  if (authChecking) return <div className="authLoading">Comprobando sesión…</div>;

  return (
    <div className="shell">
      {authChecking && <div className="authLoading">Comprobando sesión…</div>}
      <aside className={menu ? "sidebar open" : "sidebar"}>
        <div className="brand">
          <div className="brandMark"><GraduationCap size={25} /></div>
          <div><strong>Itzamná</strong><span>Control escolar</span></div>
          <button className="mobileClose" onClick={() => setMenu(false)}><X size={20} /></button>
        </div>
        <nav>
          <p className="navLabel">OPERACIÓN</p>
          {nav.map(([label, Icon]) => (
            <button key={label} className={active === label ? "active" : ""}
              onClick={() => go(label)}>
              <Icon size={19} /><span>{label}</span>{label === "Ingresos" && <em>3</em>}
            </button>
          ))}
        </nav>
        <div className="sessionActions"><span>{userName}</span><button className="logoutButton" onClick={signOut} aria-label="Cerrar sesión" title="Cerrar sesión"><LogOut size={16} /> Cerrar sesión</button></div>
        <div className="user"><div className="avatar">CA</div><div><strong>Claudia A.</strong><span>Coordinación</span></div><ChevronDown size={16} /></div>
      </aside>
      {menu && <button className="scrim" onClick={() => setMenu(false)} />}

      <main>
        <header>
          <button className="menuButton" onClick={() => setMenu(true)}><Menu size={22} /></button>
          <div className="cycle"><span>Ciclo escolar</span><button>2025 – 2026 <ChevronDown size={15} /></button></div>
          <div className="headerRight"><button className="iconButton" aria-label="Notificaciones"><Bell size={20} /><i /></button></div>
        </header>

        <div className="content">
          {active !== "Inicio" ? (
            <ModuleView name={active} openForm={setModal} />
          ) : <>
          <section className="welcome">
            <div><p className="eyebrow">OPERACIÓN DEL DÍA</p><h1>¿Qué necesitas registrar?</h1><p>Accede a las tareas habituales de caja y revisa los últimos movimientos.</p></div>
            <div className="actions">
              <button className="secondary" onClick={() => setModal("transferencia")}><Banknote size={18} /> Registrar transferencia</button>
              <button className="primary" onClick={() => setModal("cobro")}><Plus size={18} /> Nuevo cobro</button>
            </div>
          </section>

          <section className="workActions">
            <button onClick={() => setModal("cobro")}><span><CircleDollarSign /></span><div><strong>Cobrar a un alumno</strong><small>Genera recibo e ingreso automáticamente</small></div><b>→</b></button>
            <button onClick={() => setModal("transferencia")}><span><Banknote /></span><div><strong>Capturar transferencia</strong><small>Registra referencia y asigna el pago</small></div><b>→</b></button>
            <button onClick={() => go("Egresos")}><span><ArrowUpRight /></span><div><strong>Registrar un egreso</strong><small>Gastos, costos y comprobantes</small></div><b>→</b></button>
          </section>

          <section className="numberBar">
            <div><span>Ingresos registrados</span><strong className="financialPositive">{money.format(summary.income)}</strong></div>
            <div><span>Egresos registrados</span><strong className="financialNegative">{money.format(summary.expense)}</strong></div>
            <div><span>Pendiente por cobrar</span><strong className="financialWarning">{money.format(summary.pending)}</strong></div>
            <button onClick={() => go("Reportes")}>Consultar reportes →</button>
          </section>

          <section className="panel movements">
            <div className="movementHead">
              <div><h2>Movimientos recientes</h2><p>Ingresos y egresos registrados</p></div>
              <label className="search"><Search size={17} /><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Buscar alumno o folio" /></label>
            </div>
            <div className="tableWrap"><table>
              <thead><tr><th>Folio</th><th>Fecha</th><th>Alumno / proveedor</th><th>Concepto</th><th>Forma / caja</th><th>Importe</th><th>Estado</th></tr></thead>
              <tbody>{visible.map(([folio, date, person, detail, method, amount, status]) =>
                <tr key={folio}><td data-label="Folio"><button className="folio">{folio}</button></td><td data-label="Fecha">{date}</td><td data-label="Alumno / proveedor" className="person">{person}</td><td data-label="Concepto">{detail}</td><td data-label="Forma / caja">{method}</td><td data-label="Importe" className={amount < 0 ? "amount negative" : "amount positive"}>{money.format(amount)}</td><td data-label="Estado"><span className={`badge ${status.toLowerCase()}`}>{status}</span></td></tr>)}
              </tbody>
            </table>{!visible.length && <div className="empty">No encontramos movimientos con esa búsqueda.</div>}</div>
            <div className="panelFooter"><span>Mostrando {visible.length} movimientos recientes</span><button onClick={() => go("Ingresos")}>Consultar todos los movimientos →</button></div>
          </section>
          </>}
        </div>
      </main>

      {modal && <QuickForm type={modal} close={() => setModal(null)} />}
    </div>
  );
}

const moduleData: Record<string, { title: string; subtitle: string; action: string; headers: string[]; rows: string[][] }> = {
  Alumnos: { title: "Alumnos", subtitle: "Matrícula y datos de contacto del ciclo actual", action: "Nuevo alumno", headers: ["Matrícula","Nombre","Grado","Tutor","Teléfono","Estado"], rows: [["CEI-0251","Sofía Martínez Pech","4° Primaria","Laura Pech","999 214 8801","Activo"],["CEI-0184","Mauricio Torres Solís","3° Primaria","Daniel Torres","999 318 5520","Activo"],["CEI-0278","Ana Paula Díaz","2° Primaria","Mónica Díaz","999 102 7743","Activo"]] },
  Cobros: { title: "Cobros y adeudos", subtitle: "Saldos por alumno, concepto y mes", action: "Nuevo cobro", headers: ["Alumno","Concepto","Mes","Cargo","Pagado","Saldo","Estado"], rows: [["Sofía Martínez Pech","Colegiatura","10 · Junio","$3,250","$3,250","$0","Pagado"],["Mauricio Torres Solís","Colegiatura","9 · Mayo","$3,250","$3,200","$50","Parcial"],["Carlos Méndez Poot","Colegiatura","10 · Junio","$3,250","$0","$3,250","Pendiente"]] },
  Ingresos: { title: "Ingresos", subtitle: "Efectivo, transferencias y depósitos por identificar", action: "Registrar transferencia", headers: ["Folio","Fecha","Alumno","Concepto","Forma","Importe","Conciliación"], rows: [["REC-00482","30 jun 2026","Sofía Martínez","Colegiatura","Efectivo","$3,250","Conciliado"],["TRF-00219","30 jun 2026","Mauricio Torres","Saldo colegiatura","Transferencia","$50","Pendiente"],["TRF-00218","29 jun 2026","Sin identificar","Por asignar","Transferencia","$3,250","No identificado"]] },
  Conciliación: { title: "Conciliación bancaria", subtitle: "Compara los movimientos semanales del banco contra los ingresos capturados", action: "Importar movimientos", headers: ["Fecha banco","Referencia","Depósito","Alumno sugerido","Ingreso registrado","Diferencia","Estado"], rows: [["30 jun 2026","MAURICIO TORRES 3A","$50","Mauricio Torres","$50","$0","Conciliado"],["29 jun 2026","PAGO COLEGIATURA","$3,250","Sin coincidencia","—","$3,250","No identificado"],["28 jun 2026","SOFIA MP JUNIO","$3,250","Sofía Martínez","$3,250","$0","Conciliado"]] },
  Egresos: { title: "Egresos", subtitle: "Costos, gastos y salidas de las cajas", action: "Nuevo egreso", headers: ["Folio","Fecha","Tipo","Partida","Descripción","Caja","Total"], rows: [["EGR-00176","29 jun 2026","Gasto","Servicios","Agua · JAPAY","Caja PyME","$1,840"],["EGR-00175","28 jun 2026","Costo","Material escolar","Papelería del mes","Caja administración","$2,460"],["EGR-00174","27 jun 2026","Gasto","Mantenimiento","Reparación de bomba","Caja PyME","$3,800"]] },
  Nómina: { title: "Nómina", subtitle: "Periodos, incidencias y pagos al personal", action: "Nueva quincena", headers: ["Periodo","Empleados","Percepciones","Descuentos","Total","Caja","Estado"], rows: [["16–30 junio 2026","24","$148,300","$6,850","$141,450","Caja PyME","Borrador"],["1–15 junio 2026","24","$147,900","$5,200","$142,700","Caja PyME","Pagada"]] },
  Traspasos: { title: "Traspasos entre cajas", subtitle: "Movimientos internos que no cuentan como ingreso ni egreso", action: "Nuevo traspaso", headers: ["Folio","Fecha","Origen","Destino","Motivo","Monto","Estado"], rows: [["TRA-00031","28 jun 2026","Caja PyME","Caja administración","Pago de nómina","$35,000","Confirmado"],["TRA-00030","25 jun 2026","Caja administración","Caja chica","Reposición","$2,000","Confirmado"]] },
  Becas: { title: "Becas y descuentos", subtitle: "Becas internas y oficiales aplicadas a la cobranza", action: "Asignar beca", headers: ["Alumno","Tipo","Porcentaje","Concepto","Vigencia","Impacto mensual","Estado"], rows: [["Valentina López","Oficial","50%","Colegiatura","Sep 2025 – Jun 2026","-$1,625","Activa"],["José Pech","Interna","30%","Colegiatura","Sep 2025 – Jun 2026","-$975","Activa"],["Mariana Solís","Oficial","100%","Colegiatura","Sep 2025 – Jun 2026","-$3,250","Activa"]] },
  Presupuesto: { title: "Presupuesto y comparación real", subtitle: "Proyección por ciclo, mes, concepto y partida", action: "Nueva proyección", headers: ["Mes","Ingresos presupuestados","Ingresos reales","Egresos presupuestados","Egresos reales","Resultado","Cumplimiento"], rows: [["Septiembre","$410,000","$402,500","$275,000","$269,400","$133,100","98%"],["Octubre","$385,000","$391,200","$271,000","$276,800","$114,400","102%"],["Junio","$330,000","$284,650","$190,000","$168,420","$116,230","86%"]] },
  Reportes: { title: "Reportes", subtitle: "Consultas numéricas y exportaciones del ciclo escolar", action: "Exportar", headers: ["Reporte","Periodo","Última actualización","Formato","Estado"], rows: [["Estado de cuenta por alumno","Ciclo 2025–2026","Hoy, 10:42","PDF / Excel","Disponible"],["Cobranza por grupo","Junio 2026","Hoy, 10:42","Excel","Disponible"],["Flujo de efectivo","Junio 2026","Ayer, 18:10","PDF / Excel","Disponible"],["Estado de resultados","Junio 2026","Ayer, 18:10","PDF / Excel","Disponible"]] },
};

function ModuleView({ name, openForm }: { name: string; openForm: (type: string) => void }) {
  const data = moduleData[name] ?? moduleData.Alumnos;
  const act = () => openForm(name === "Cobros" ? "cobro" : name === "Ingresos" ? "transferencia" : name);
  return <section className="modulePage">
    <div className="moduleHead"><div><p className="eyebrow">CICLO 2025 – 2026</p><h1>{data.title}</h1><p>{data.subtitle}</p></div><button className="primary" onClick={act}><Plus size={18}/>{data.action}</button></div>
    <div className="moduleTools"><label className="search"><Search size={18}/><input placeholder={`Buscar en ${data.title.toLowerCase()}…`}/></label><button className="secondary">Filtros <ChevronDown size={16}/></button></div>
    <div className="panel moduleTable"><div className="tableWrap"><table><thead><tr>{data.headers.map(h=><th key={h}>{h}</th>)}</tr></thead><tbody>{data.rows.map((row,i)=><tr key={i}>{row.map((cell,j)=><td data-label={data.headers[j]} className={[j===1?"person":"", getFinancialTone(name, data.headers[j], cell, row)].filter(Boolean).join(" ")} key={j}>{cell}</td>)}</tr>)}</tbody></table></div><div className="panelFooter"><span>{data.rows.length} registros de demostración</span><button>Siguiente página →</button></div></div>
  </section>;
}

function numberFromCell(value: string) {
  const parsed = Number(value.replace(/[^\d.-]/g, ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

function getFinancialTone(module: string, header: string, cell: string, row: string[]) {
  const value = numberFromCell(cell);

  if (module === "Presupuesto") {
    if (header === "Ingresos reales") return value >= numberFromCell(row[1]) ? "financialPositive" : "financialNegative";
    if (header === "Egresos reales") return value <= numberFromCell(row[3]) ? "financialPositive" : "financialNegative";
    if (header === "Resultado") return value >= 0 ? "financialPositive" : "financialNegative";
    if (header === "Cumplimiento") return value >= 100 ? "financialPositive" : "financialWarning";
  }

  if (module === "Ingresos" && header === "Importe") return "financialPositive";
  if (module === "Cobros" && header === "Pagado") return value > 0 ? "financialPositive" : "";
  if (module === "Cobros" && header === "Saldo") return value > 0 ? "financialNegative" : "financialPositive";
  if (module === "Conciliación" && header === "Diferencia") return value > 0 ? "financialNegative" : "financialPositive";
  if (module === "Egresos" && header === "Total") return "financialNegative";
  if (module === "Nómina" && header === "Total") return "financialNegative";
  if (module === "Becas" && header === "Impacto mensual") return value < 0 ? "financialNegative" : "";

  return "";
}
const formTitles: Record<string, string> = {
  cobro: "Nuevo cobro en caja", transferencia: "Registrar transferencia",
  Alumnos: "Registrar alumno", Conciliación: "Importar movimientos bancarios",
  Egresos: "Registrar egreso", Nómina: "Preparar nueva quincena",
  Traspasos: "Registrar traspaso", Becas: "Asignar beca o descuento",
  Presupuesto: "Crear proyección", Reportes: "Exportar reporte",
};

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function QuickFormLegacy({ type, close }: { type: string; close: () => void }) {
  const payment = type === "cobro" || type === "transferencia";
  return <div className="modalLayer" role="dialog" aria-modal="true">
    <button className="backdrop" onClick={close} />
    <form className="modal" onSubmit={(e) => { e.preventDefault(); close(); }}>
      <div className="modalHead"><div><p className="eyebrow">CAPTURA</p><h2>{formTitles[type] ?? `Nuevo registro de ${type.toLowerCase()}`}</h2></div><button type="button" className="iconButton" onClick={close}><X size={20} /></button></div>
      {payment ? <><label>Alumno<input required placeholder="Buscar sin importar acentos, nombre o matrícula…" /></label>
      <div className="formRow"><label>Concepto<select required defaultValue=""><option value="" disabled>Seleccionar</option><option>Colegiatura</option><option>Estancia</option><option>Inscripción</option><option>Constancia</option><option>Club de tareas</option><option>Otro</option></select></label><label>Mes del ciclo<select defaultValue="10"><option value="10">10 · Junio</option><option value="9">9 · Mayo</option></select></label></div>
      <div className="formRow"><label>Monto<input required type="number" min=".01" step=".01" placeholder="$ 0.00" /></label><label>{type === "cobro" ? "Caja destino" : "Referencia bancaria"}<input required placeholder={type === "cobro" ? "Caja administración" : "Ej. Mauricio Torres"} /></label></div>
      <p className="formNote">{type === "cobro" ? "Al confirmar se generará el recibo y el ingreso en una sola operación." : "Puede guardarse sin identificar y asignarse posteriormente a cualquier concepto o saldo parcial."}</p></>
      : <><label>Descripción o nombre<input required placeholder={`Datos principales para ${type.toLowerCase()}…`} /></label>
      <div className="formRow"><label>Fecha<input required type="date" defaultValue="2026-06-30" /></label><label>Importe o valor<input required placeholder={type === "Alumnos" ? "Grado / matrícula" : "$ 0.00"} /></label></div>
      <label>Observaciones<textarea placeholder="Información adicional…" /></label>
      <p className="formNote">Este formulario se conectará al registro definitivo de Supabase; por ahora permite validar el flujo y los campos con la coordinadora.</p></>}
      <div className="modalActions"><button type="button" className="secondary" onClick={close}>Cancelar</button><button className="primary">Confirmar registro</button></div>
    </form>
  </div>;
}

function QuickForm({ type, close }: { type: string; close: () => void }) {
  const supabase = useMemo(() => createClient(), []);
  const payment = type === "cobro" || type === "transferencia";
  const [name, setName] = useState("");
  const [enrollment, setEnrollment] = useState("");
  const [amount, setAmount] = useState("");
  const [reference, setReference] = useState("");
  const [concept, setConcept] = useState("Colegiatura");
  const [description, setDescription] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    const { data: userData } = await supabase.auth.getUser();
    const user = userData.user;
    if (!user) {
      window.location.assign("/login");
      return;
    }

    try {
      if (type === "Alumnos") {
        const { data: cycle } = await supabase.from("school_cycles").select("id").eq("active", true).single();
        if (!cycle) throw new Error("No hay un ciclo escolar activo.");
        const parts = name.trim().split(/\s+/);
        const firstName = parts.shift() || name.trim();
        const lastName = parts.join(" ") || "Pendiente";
        const { error } = await supabase.from("students").insert({
          enrollment: enrollment.trim(), first_name: firstName, last_name: lastName,
          level: "Primaria", grade: description.trim() || "Pendiente", cycle_id: cycle.id,
        });
        if (error) throw error;
      } else if (payment) {
        const { data: account } = await supabase.from("accounts").select("id").eq("kind", type === "cobro" ? "efectivo" : "banco").eq("active", true).limit(1).maybeSingle();
        if (!account) throw new Error("No hay una cuenta financiera configurada.");
        const { data: student } = name.trim()
          ? await supabase.from("students").select("id").or(`enrollment.ilike.%${name.trim()}%,first_name.ilike.%${name.trim()}%,last_name.ilike.%${name.trim()}%`).limit(1).maybeSingle()
          : { data: null };
        if (type === "cobro") {
          if (!student) throw new Error("Selecciona un alumno válido para generar el recibo.");
          const { data: cycle } = await supabase.from("school_cycles").select("id").eq("active", true).single();
          const { data: paymentConcept } = await supabase.from("payment_concepts").select("id,base_amount").eq("name", concept.trim()).maybeSingle();
          if (!cycle || !paymentConcept) throw new Error("No existe un ciclo o concepto de cobro configurado.");
          let { data: charge } = await supabase.from("charges").select("id").eq("student_id", student.id).eq("cycle_id", cycle.id).eq("concept_id", paymentConcept.id).in("status", ["pendiente", "parcial"]).limit(1).maybeSingle();
          if (!charge) {
            const { data: createdCharge, error: chargeError } = await supabase.from("charges").insert({
              student_id: student.id, cycle_id: cycle.id, concept_id: paymentConcept.id,
              gross_amount: Number(paymentConcept.base_amount) || Number(amount), due_on: date,
            }).select("id").single();
            if (chargeError) throw chargeError;
            charge = createdCharge;
          }
          const { error } = await supabase.rpc("register_cash_payment", {
            p_student_id: student.id, p_account_id: account.id, p_method: "efectivo",
            p_notes: concept.trim(), p_allocations: [{ charge_id: charge.id, amount: Number(amount) }],
          });
          if (error) throw error;
        } else {
          const { error } = await supabase.from("incomes").insert({
            student_id: student?.id ?? null, account_id: account.id, paid_on: date,
            amount: Number(amount), payment_method: "transferencia",
            bank_reference: reference.trim() || null, created_by: user.id,
          });
          if (error) throw error;
        }
        window.dispatchEvent(new Event("cei:data-changed"));
        close();
        return;
      } else if (payment && false) {
        const accountName = type === "cobro" ? "Caja administración" : "Banco principal";
        const { data: account } = await supabase.from("accounts").select("id").eq("name", accountName).single();
        if (!account) throw new Error("No hay una cuenta financiera configurada.");
        const { data: student } = name.trim()
          ? await supabase.from("students").select("id").or(`enrollment.ilike.%${name.trim()}%,first_name.ilike.%${name.trim()}%,last_name.ilike.%${name.trim()}%`).limit(1).maybeSingle()
          : { data: null };
        const { error } = await supabase.from("incomes").insert({
          student_id: student?.id ?? null, account_id: account!.id, paid_on: date,
          amount: Number(amount), payment_method: type === "cobro" ? "efectivo" : "transferencia",
          bank_reference: reference.trim() || null, created_by: user!.id,
        });
        if (error) throw error;
      } else if (type === "Egresos") {
        const { data: account } = await supabase.from("accounts").select("id").eq("name", "Caja administración").single();
        const { data: category } = await supabase.from("expense_categories").select("id").eq("name", "Servicios").single();
        if (!account || !category) throw new Error("Faltan catálogos financieros iniciales.");
        const { error } = await supabase.from("expenses").insert({
          account_id: account.id, category_id: category.id, spent_on: date,
          description: description.trim() || name.trim(), subtotal: Number(amount),
          payment_method: "efectivo", created_by: user.id,
        });
        if (error) throw error;
      } else if (type === "Traspasos") {
        const { data: accounts } = await supabase.from("accounts").select("id,name").in("name", ["Caja administración", "Banco principal"]);
        const source = accounts?.find((account) => account.name === "Caja administración");
        const destination = accounts?.find((account) => account.name === "Banco principal");
        if (!source || !destination) throw new Error("Faltan cuentas financieras iniciales.");
        const { error } = await supabase.from("transfers").insert({
          source_account_id: source.id, destination_account_id: destination.id,
          transferred_on: date, amount: Number(amount), reason: description.trim() || "Traspaso interno", created_by: user.id,
        });
        if (error) throw error;
      } else {
        throw new Error("Este módulo todavía requiere conectar su formulario específico.");
      }
      close();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo guardar el registro.");
    } finally {
      setBusy(false);
    }
  }

  return <div className="modalLayer" role="dialog" aria-modal="true">
    <button className="backdrop" onClick={close} />
    <form className="modal" onSubmit={save}>
      <div className="modalHead"><div><p className="eyebrow">CAPTURA</p><h2>{formTitles[type] ?? `Nuevo registro de ${type.toLowerCase()}`}</h2></div><button type="button" className="iconButton" onClick={close}><X size={20} /></button></div>
      {payment ? <><label>Alumno<input value={name} onChange={(event) => setName(event.target.value)} placeholder="Nombre o matrícula" /></label>
        <div className="formRow"><label>Fecha<input required type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label><label>Monto<input required type="number" min=".01" step=".01" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="$ 0.00" /></label></div>
        <label>{type === "cobro" ? "Concepto" : "Referencia bancaria"}<input required={type === "transferencia"} value={type === "cobro" ? concept : reference} onChange={(event) => type === "cobro" ? setConcept(event.target.value) : setReference(event.target.value)} placeholder={type === "cobro" ? "Colegiatura" : "Referencia del depósito"} /></label>
      </> : <><label>{type === "Alumnos" ? "Nombre completo" : "Descripción"}<input required value={name} onChange={(event) => setName(event.target.value)} placeholder="Escribe la información principal" /></label>
        <div className="formRow"><label>Fecha<input required type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label><label>{type === "Alumnos" ? "Matrícula" : "Importe"}<input required={type !== "Alumnos"} type={type === "Alumnos" ? "text" : "number"} min={type === "Alumnos" ? undefined : ".01"} step={type === "Alumnos" ? undefined : ".01"} value={type === "Alumnos" ? enrollment : amount} onChange={(event) => type === "Alumnos" ? setEnrollment(event.target.value) : setAmount(event.target.value)} placeholder={type === "Alumnos" ? "CEI-0001" : "$ 0.00"} /></label></div>
        {type === "Alumnos" && <label>Grado<textarea value={description} onChange={(event) => setDescription(event.target.value)} placeholder="Ej. 4° Primaria" /></label>}
      </>}
      {message && <p className="formError">{message}</p>}
      <div className="modalActions"><button type="button" className="secondary" onClick={close}>Cancelar</button><button className="primary" disabled={busy}>{busy ? "Guardando…" : "Guardar en Supabase"}</button></div>
    </form>
  </div>;
}
