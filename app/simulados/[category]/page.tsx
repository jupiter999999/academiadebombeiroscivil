import { notFound, redirect } from "next/navigation";
import { AppShell } from "@/components/app-shell";
import { QuizRunner } from "@/components/quiz-runner";
import { createClient } from "@/lib/supabase/server";
import { CATEGORIES, type CategoryKey } from "@/lib/constants";
import type { Profile, Question } from "@/lib/types";

export default async function SimulationPage({ params }: { params: Promise<{ category: string }> }) {
  const { category } = await params;
  if (!(category in CATEGORIES)) notFound();

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/entrar");
  const { data: profile } = await supabase.from("profiles").select("*").eq("id", user.id).single();
  if (!profile) redirect("/entrar");

  const p = profile as Profile;
  const now = Date.now();
  const access = p.role === "admin" || new Date(p.trial_ends_at).getTime() > now ||
    (!!p.access_ends_at && new Date(p.access_ends_at).getTime() > now);
  if (!access) redirect("/assinatura");

  const { data: questions } = await supabase.from("questions")
    .select("*").eq("category", category).eq("active", true);

  return <AppShell admin={p.role === "admin"}>
    <div className="page-head"><span className="eyebrow">SIMULADO: {CATEGORIES[category as CategoryKey].short}</span>
    <h1>{CATEGORIES[category as CategoryKey].title}</h1></div>
    <QuizRunner questions={(questions ?? []) as Question[]} category={category}/>
  </AppShell>;
}
