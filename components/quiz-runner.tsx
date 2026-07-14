"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, Clock3, XCircle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { Question } from "@/lib/types";

function shuffled<T>(items: T[]) {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

/**
 * Coloca a alternativa correta em uma posição determinada e embaralha
 * somente as incorretas. Assim a resposta correta não fica presa em B
 * e a distribuição fica equilibrada entre A, B, C e D.
 */
function prepareQuestion(question: Question, targetCorrectIndex: number): Question {
  const correctOption = question.options[question.correct_answer];
  const wrongOptions = question.options.filter((_, index) => index !== question.correct_answer);
  const mixedWrongOptions = shuffled(wrongOptions);
  const options = [...mixedWrongOptions];
  options.splice(Math.min(targetCorrectIndex, options.length), 0, correctOption);

  return {
    ...question,
    options,
    correct_answer: Math.min(targetCorrectIndex, options.length - 1)
  };
}

export function QuizRunner({ questions, category }: { questions: Question[]; category: string }) {
  const router = useRouter();
  const [count, setCount] = useState(10);
  const [started, setStarted] = useState(false);
  const [quiz, setQuiz] = useState<Question[]>([]);
  const [index, setIndex] = useState(0);
  const [chosen, setChosen] = useState<number | null>(null);
  const [correct, setCorrect] = useState(0);
  const [saving, setSaving] = useState(false);

  const current = quiz[index];
  const percent = quiz.length ? Math.round((correct / quiz.length) * 100) : 0;
  const finished = started && quiz.length > 0 && index >= quiz.length;

  function begin() {
    const selected = shuffled(questions).slice(0, Math.min(count, questions.length));
    const positionCycle = shuffled([0, 1, 2, 3]);
    const prepared = selected.map((question, questionIndex) =>
      prepareQuestion(question, positionCycle[questionIndex % positionCycle.length])
    );

    setQuiz(prepared);
    setIndex(0);
    setChosen(null);
    setCorrect(0);
    setStarted(true);
  }

  function answer(i: number) {
    if (chosen !== null) return;
    setChosen(i);
    if (i === current.correct_answer) setCorrect(value => value + 1);
  }

  async function next() {
    if (index + 1 < quiz.length) {
      setIndex(value => value + 1);
      setChosen(null);
      return;
    }

    setIndex(quiz.length);
    setSaving(true);
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (user) {
      await supabase.from("attempts").insert({
        user_id: user.id,
        category,
        total_questions: quiz.length,
        correct_answers: correct,
        score_percent: Math.round((correct / quiz.length) * 100)
      });
    }
    setSaving(false);
  }

  if (!started) return <div className="quiz-setup premium-surface">
    <span className="eyebrow">NOVO SIMULADO</span>
    <h1>Quantas questões?</h1>
    <p>As perguntas e as alternativas serão embaralhadas a cada tentativa.</p>
    <div className="count-selector">{[10,20,50].map(n =>
      <button key={n} className={count === n ? "selected" : ""} onClick={() => setCount(n)}>
        <strong>{n}</strong><span>questões</span>
      </button>
    )}</div>
    <button className="button primary large" onClick={begin}>COMEÇAR SIMULADO</button>
  </div>;

  if (finished) return <div className="quiz-result premium-surface">
    <div className="result-check"><CheckCircle2/></div>
    <span className="eyebrow">SIMULADO CONCLUÍDO</span>
    <h1>{percent}% de aproveitamento</h1>
    <p>Você acertou {correct} de {quiz.length} questões.</p>
    <div className="result-actions">
      <button className="button primary" onClick={() => { setStarted(false); setIndex(0); }}>Fazer novamente</button>
      <button className="button outline" onClick={() => router.push("/dashboard")}>Voltar ao painel</button>
    </div>
  </div>;

  if (!current) return <p>Não existem questões disponíveis nesta categoria.</p>;

  const isCorrect = chosen === current.correct_answer;
  return <div className="quiz-card premium-surface">
    <div className="quiz-progress-head">
      <span>Questão {index + 1} de {quiz.length}</span>
      <span><Clock3 size={16}/> Simulado</span>
    </div>
    <div className="progress-line"><i style={{ width: `${((index + 1) / quiz.length) * 100}%` }}/></div>
    <h2>{current.statement}</h2>
    <div className="quiz-options">{current.options.map((option, i) => {
      let cls = "quiz-option";
      if (chosen !== null && i === current.correct_answer) cls += " correct";
      if (chosen === i && i !== current.correct_answer) cls += " wrong";
      return <button className={cls} key={`${current.id}-${i}`} onClick={() => answer(i)} disabled={chosen !== null}>
        <span>{String.fromCharCode(65+i)}</span>{option}
      </button>;
    })}</div>
    {chosen !== null && <div className={`answer-box ${isCorrect ? "success" : "failure"}`}>
      {isCorrect ? <CheckCircle2/> : <XCircle/>}
      <div><strong>{isCorrect ? "Correto!" : "Resposta incorreta"}</strong><p>{current.explanation}</p></div>
    </div>}
    {chosen !== null && <button className="button primary next-button" onClick={next} disabled={saving}>
      {index + 1 === quiz.length ? (saving ? "Salvando..." : "Ver resultado") : "Próxima questão"}
    </button>}
  </div>;
}
