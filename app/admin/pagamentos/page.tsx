import { AppShell } from "@/components/app-shell";
import { ApprovePaymentButton } from "@/components/admin-actions";
import { requireAdmin } from "@/lib/admin";
import type { PaymentRequest } from "@/lib/types";

export default async function PaymentsPage() {
  const { supabase } = await requireAdmin();
  const { data } = await supabase.from("payment_requests")
    .select("*, profiles(full_name,email)").order("created_at", { ascending: false }).limit(200);
  const payments = (data ?? []) as PaymentRequest[];
  return <AppShell admin><div className="page-head"><span className="eyebrow">ADMIN</span><h1>Pagamentos</h1></div>
    <div className="admin-table">{payments.map(p => {
      const proofUrl = p.proof_path ? supabase.storage.from("payment-proofs").getPublicUrl(p.proof_path).data.publicUrl : "#";
      return <div className="admin-row payment-row" key={p.id}>
        <div><strong>{p.profiles?.full_name ?? "Aluno"}</strong><span>{p.profiles?.email}</span></div>
        <strong>R$ {Number(p.amount).toFixed(2)}</strong><span className={`status-chip ${p.status}`}>{p.status}</span>
        <a className="text-link" href={proofUrl} target="_blank">Ver comprovante</a>
        {p.status === "pending" && <ApprovePaymentButton id={p.id} userId={p.user_id}/>}
      </div>;
    })}</div>
  </AppShell>;
}
