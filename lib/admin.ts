import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Profile } from "./types";

export async function requireAdmin() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/entrar");
  const { data: profile } = await supabase.from("profiles").select("*").eq("id", user.id).single();
  if (!profile || (profile as Profile).role !== "admin") redirect("/dashboard");
  return { supabase, profile: profile as Profile };
}
