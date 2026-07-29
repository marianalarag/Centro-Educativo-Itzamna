import { notFound } from "next/navigation";
import Home from "../page";

const modules: Record<string, string> = {
  alumnos: "Alumnos",
  cobros: "Cobros",
  ingresos: "Ingresos",
  conciliacion: "Conciliación",
  egresos: "Egresos",
  nomina: "Nómina",
  traspasos: "Traspasos",
  becas: "Becas",
  presupuesto: "Presupuesto",
  reportes: "Reportes",
};

export default async function ModulePage({
  params,
}: {
  params: Promise<{ module: string }>;
}) {
  const { module } = await params;
  const active = modules[module];
  if (!active) notFound();
  return <Home initialActive={active} />;
}
