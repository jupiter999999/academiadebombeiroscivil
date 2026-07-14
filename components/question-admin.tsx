"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";
import type { Question } from "@/lib/types";

export function QuestionAdmin({ initial }: { initial: Question[] }) {
  const router = useRouter();
  const [category, setCategory] = useState("NR");
  const visible = initial.filter(q => q.category === category).slice(0, 100);

  async function toggle(q: Question) {
    const { error } = await createClient().from("questions").update({ active: !q.active }).eq("id", q.id);
    if (error) alert(error.message); else router.refresh();
  }

  return <div>
    <div className="filter-tabs">{["NR","NT","Extintores","Mapas","APH","Mangueiras"].map(c =>
      <button key={c} className={category === c ? "active" : ""} onClick={() => setCategory(c)}>{c}</button>)}</div>
    <div className="question-list">{visible.map((q, i) => <article key={q.id}>
      <span>{i+1}</span><div><strong>{q.statement}</strong><p>{q.explanation}</p></div>
      <button className={`status-chip ${q.active ? "active" : "blocked"}`} onClick={() => toggle(q)}>{q.active ? "Ativa" : "Inativa"}</button>
    </article>)}</div>
  </div>;
}
