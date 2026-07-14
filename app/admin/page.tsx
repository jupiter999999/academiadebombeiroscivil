import Link from "next/link";
import { AppShell } from "@/components/app-shell";
import { requireAdmin } from "@/lib/admin";
import { CreditCard, FileQuestion, Users } from "lucide-react";

export default async function AdminPage() {
  const { supabase, profile } = await requireAdmin();
  const [{ count: users }, { count: questions }, { count: payments }] = await Promise.all([
    supabase.from("profiles").select("*", { count: "exact", head: true }),
    supabase.from("questions").select("*", { count: "exact", head: true }),
    supabase.from("payment_requests").select("*", { count: "exact", head: true }).eq("status", "pending")
  ]);
  return <AppShell admin>
    <div className="page-head"><span className="eyebrow">ADMINISTRAÇÃO</span><h1>Painel administrativo</h1><p>Gerencie alunos, conteúdo e pagamentos.</p></div>
    <div className="admin-cards">
      <Link href="/admin/alunos"><Users/><span>Alunos cadastrados</span><strong>{users ?? 0}</strong></Link>
      <Link href="/admin/questoes"><FileQuestion/><span>Questões no banco</span><strong>{questions ?? 0}</strong></Link>
      <Link href="/admin/pagamentos"><CreditCard/><span>Pagamentos pendentes</span><strong>{payments ?? 0}</strong></Link>
    </div>
  </AppShell>;
}
