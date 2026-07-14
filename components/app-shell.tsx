import Link from "next/link";
import {
  BarChart3, BookOpen, CreditCard, Gauge, Heart, History, Settings, ShieldCheck, Users
} from "lucide-react";
import { Logo } from "./logo";
import { LogoutButton } from "./logout-button";
import type { ReactNode } from "react";

export function AppShell({
  children, admin = false
}: { children: ReactNode; admin?: boolean }) {
  return (
    <div className="app-layout">
      <aside className="sidebar">
        <Logo dark />
        <nav>
          <Link className="nav-link" href="/dashboard"><Gauge size={18}/> Visão geral</Link>
          <Link className="nav-link" href="/dashboard#materias"><BookOpen size={18}/> Simulados</Link>
          <Link className="nav-link" href="/dashboard#desempenho"><BarChart3 size={18}/> Desempenho</Link>
          <Link className="nav-link" href="/dashboard#historico"><History size={18}/> Histórico</Link>
          <Link className="nav-link" href="/dashboard#favoritos"><Heart size={18}/> Favoritos</Link>
          <Link className="nav-link" href="/assinatura"><CreditCard size={18}/> Assinatura</Link>
          {admin && <>
            <div className="nav-separator">ADMINISTRAÇÃO</div>
            <Link className="nav-link" href="/admin"><ShieldCheck size={18}/> Painel admin</Link>
            <Link className="nav-link" href="/admin/questoes"><Settings size={18}/> Questões</Link>
            <Link className="nav-link" href="/admin/alunos"><Users size={18}/> Alunos</Link>
            <Link className="nav-link" href="/admin/pagamentos"><CreditCard size={18}/> Pagamentos</Link>
          </>}
        </nav>
        <LogoutButton />
      </aside>
      <main className="app-main">{children}</main>
    </div>
  );
}
