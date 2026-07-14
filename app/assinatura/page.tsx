import { redirect } from "next/navigation";
import { AppShell } from "@/components/app-shell";
import { PaymentForm } from "@/components/payment-form";
import { createClient } from "@/lib/supabase/server";
import type { Profile } from "@/lib/types";

export default async function SubscriptionPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/entrar");
  const { data: profile } = await supabase.from("profiles").select("*").eq("id", user.id).single();
  if (!profile) redirect("/entrar");
  return <AppShell admin={(profile as Profile).role === "admin"}>
    <div className="page-head"><span className="eyebrow">ASSINATURA</span><h1>Mantenha seu acesso ativo</h1>
    <p>O pagamento é conferido manualmente e libera 30 dias de acesso.</p></div>
    <PaymentForm/>
  </AppShell>;
}
