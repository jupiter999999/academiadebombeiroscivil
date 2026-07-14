import Link from "next/link";
import { redirect } from "next/navigation";
import { AppShell } from "@/components/app-shell";
import { StatusBanner } from "@/components/status-banner";
import { createClient } from "@/lib/supabase/server";
import { CATEGORIES } from "@/lib/constants";
import type { Attempt, Profile } from "@/lib/types";
import { ArrowRight, Award, Flame, Target } from "lucide-react";

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/entrar");

  const [{ data: profile }, { data: attempts }] = await Promise.all([
    supabase.from("profiles").select("*").eq("id", user.id).single(),
    supabase.from("attempts").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(10)
  ]);

  if (!profile) redirect("/entrar");
  const typedProfile = profile as Profile;
  const typedAttempts = (attempts ?? []) as Attempt[];
  const avg = typedAttempts.length ? Math.round(typedAttempts.reduce((a, x) => a + x.score_percent, 0) / typedAttempts.length) : 0;
  const best = typedAttempts.length ? Math.max(...typedAttempts.map(x => x.score_percent)) : 0;
  const now = Date.now();
  const hasAccess = typedProfile.role === "admin" ||
    new Date(typedProfile.trial_ends_at).getTime() > now ||
    (!!typedProfile.access_ends_at && new Date(typedProfile.access_ends_at).getTime() > now);

  return <AppShell admin={typedProfile.role === "admin"}>
    <div className="dashboard-head">
      <div><span className="eyebrow">ÁREA DO ALUNO</span><h1>Olá, {typedProfile.full_name.split(" ")[0]}!</h1><p>Continue seus estudos e acompanhe sua evolução.</p></div>
      <div className="avatar">{typedProfile.full_name.charAt(0).toUpperCase()}</div>
    </div>
    <StatusBanner profile={typedProfile}/>
    <section className="metrics">
      <article><Target/><span>Taxa média</span><strong>{avg}%</strong></article>
      <article><Award/><span>Melhor pontuação</span><strong>{best}%</strong></article>
      <article><Flame/><span>Simulados realizados</span><strong>{typedAttempts.length}</strong></article>
    </section>
    <section id="materias" className="section-block">
      <div className="section-title"><div><span className="eyebrow">CONTEÚDO</span><h2>Escolha o que deseja estudar</h2></div></div>
      <div className="category-grid">
        {Object.entries(CATEGORIES).map(([key, category]) => {
          const Icon = category.icon;
          return <article className="study-card" key={key}>
            <div className="study-icon"><Icon/></div>
            <span>{category.short}</span><h3>{category.title}</h3><p>{category.description}</p>
            <div className="study-card-foot"><small>50 questões</small>
              {hasAccess ? <Link href={`/simulados/${key}`} aria-label={`Estudar ${category.title}`}><ArrowRight/></Link> :
                <Link href="/assinatura" aria-label="Renovar"><ArrowRight/></Link>}
            </div>
          </article>;
        })}
      </div>
    </section>
    <section id="historico" className="section-block">
      <div className="section-title"><h2>Últimos resultados</h2></div>
      <div className="history-table">
        {typedAttempts.length === 0 ? <p className="empty-state">Você ainda não realizou simulados.</p> :
          typedAttempts.map(a => <div className="history-row" key={a.id}>
            <strong>{CATEGORIES[a.category as keyof typeof CATEGORIES]?.title ?? a.category}</strong>
            <span>{a.correct_answers}/{a.total_questions} acertos</span>
            <b>{a.score_percent}%</b>
            <time>{new Date(a.created_at).toLocaleDateString("pt-BR")}</time>
          </div>)}
      </div>
    </section>
  </AppShell>;
}
