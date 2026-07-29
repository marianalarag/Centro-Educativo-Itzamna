import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Control Escolar | Centro Educativo Itzamná",
  description: "Sistema de cobros, ingresos y egresos",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
