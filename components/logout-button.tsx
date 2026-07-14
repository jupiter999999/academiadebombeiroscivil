"use client";

import { LogOut } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";

export function LogoutButton() {
  const router = useRouter();
  async function logout() {
    await createClient().auth.signOut();
    router.replace("/entrar");
    router.refresh();
  }
  return <button className="nav-link danger" onClick={logout}><LogOut size={18}/> Sair</button>;
}
