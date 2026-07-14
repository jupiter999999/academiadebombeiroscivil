import { AppShell } from "@/components/app-shell";
import { QuestionAdmin } from "@/components/question-admin";
import { requireAdmin } from "@/lib/admin";
import type { Question } from "@/lib/types";

export default async function QuestionsPage() {
  const { supabase } = await requireAdmin();
  const { data } = await supabase.from("questions").select("*").order("created_at", { ascending: true }).limit(1000);
  return <AppShell admin><div className="page-head"><span className="eyebrow">ADMIN</span><h1>Banco de questões</h1>
  <p>Ative ou desative perguntas. O cadastro completo pode ser ampliado na próxima etapa.</p></div>
  <QuestionAdmin initial={(data ?? []) as Question[]}/></AppShell>;
}
