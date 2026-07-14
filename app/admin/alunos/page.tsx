import { AppShell } from "@/components/app-shell";
import { SetUserStatus } from "@/components/admin-actions";
import { requireAdmin } from "@/lib/admin";
import type { Profile } from "@/lib/types";

export default async function UsersPage() {
  const { supabase } = await requireAdmin();
  const { data } = await supabase.from("profiles").select("*").order("created_at", { ascending: false }).limit(200);
  const profiles = (data ?? []) as Profile[];
  return <AppShell admin><div className="page-head"><span className="eyebrow">ADMIN</span><h1>Alunos</h1></div>
    <div className="admin-table">{profiles.map(p => <div className="admin-row" key={p.id}>
      <div><strong>{p.full_name}</strong><span>{p.email}</span></div><span className={`status-chip ${p.subscription_status}`}>{p.subscription_status}</span>
      <time>{new Date(p.created_at).toLocaleDateString("pt-BR")}</time>
      <div className="row-actions"><SetUserStatus userId={p.id} status="active"/><SetUserStatus userId={p.id} status="blocked"/></div>
    </div>)}</div>
  </AppShell>;
}
