import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Academia Bombeiro Civil",
  description: "Plataforma profissional de simulados para Bombeiro Civil.",
  icons: { icon: "/icon.svg" }
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
