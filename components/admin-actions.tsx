"use client";

import { createClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";

export function ApprovePaymentButton({ id, userId }: { id: string; userId: string }) {
  const router = useRouter();
  async function approve() {
    const supabase = createClient();
    const { error } = await supabase.rpc("approve_payment", { payment_id: id, target_user_id: userId });
    if (error) alert(error.message); else router.refresh();
  }
  return <button className="button primary small" onClick={approve}>Aprovar +30 dias</button>;
}

export function SetUserStatus({ userId, status }: { userId: string; status: "active" | "blocked" }) {
  const router = useRouter();
  async function change() {
    const supabase = createClient();
    const { error } = await supabase.rpc("admin_set_user_status", { target_user_id: userId, new_status: status });
    if (error) alert(error.message); else router.refresh();
  }
  return <button className={`button small ${status === "blocked" ? "danger-button" : "outline"}`} onClick={change}>
    {status === "blocked" ? "Bloquear" : "Ativar"}
  </button>;
}
