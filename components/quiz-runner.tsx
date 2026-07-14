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

function shuffleQuestionOptions(question: Question): Question {
  const optionsWithOriginalIndex = question.options.map((option, originalIndex) => ({
    option,
    originalIndex
  }));

  const shuffledOptions = shuffled(optionsWithOriginalIndex);
  const newCorrectAnswer = shuffledOptions.findIndex(
    item => item.originalIndex === question.correct_answer
  );

  return {
    ...question,
    options: shuffledOptions.map(item => item.option),
    correct_answer: newCorrectAnswer
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
    const selectedQuestions = shuffled(questions)
      .slice(0, Math.min(count, questions.length))
      .map(shuffleQuestionOptions);

    setQuiz(selectedQuestions);
    setIndex(0);
    setChosen(null);
    setCorrect(0);
    setStarted(true);
  }

  function answer(i: number) {
    if (chosen !== null) return;
    setChosen(i);
    if (i === current.correct_answer) setCorrect(x => x + 1);
  }

  async function next() {
    if (index + 1 < quiz.length) {
      setIndex(x => x + 1); setChosen(null);
    } else {
      const finalCorrect = correct;
      setIndex(quiz.length);
      setSaving(true);
      const supabase = createClient();
      const { data: { user } } = await supabase.auth.getUser();
      if (user) await supabase.from("attempts").insert({
        user_id: user.id,
        category,
        total_questions: quiz.length,
        correct_answers: finalCorrect,
        score_percent: Math.round((finalCorrect / quiz.length) * 100)
      });
      setSaving(false);
    }
  }

  if (!started) return <div className="quiz-setup">
    <span className="eyebrow">NOVO SIMULADO</span><h1>Quantas questões?</h1>
    <p>As perguntas serão selecionadas aleatoriamente.</p>
    <div className="count-selector">{[10,20,50].map(n =>
      <button key={n} className={count === n ? "selected" : ""} onClick={() => setCount(n)}><strong>{n}</strong><span>questões</span></button>
    )}</div>
    <button className="button primary large" onClick={begin}>COMEÇAR SIMULADO</button>
  </div>;

  if (finished) return <div className="quiz-result">
    <div className="result-check"><CheckCircle2/></div><span className="eyebrow">SIMULADO CONCLUÍDO</span>
    <h1>{percent}% de aproveitamento</h1><p>Você acertou {correct} de {quiz.length} questões.</p>
    <div className="result-actions"><button className="button primary" onClick={() => { setStarted(false); setIndex(0); }}>Fazer novamente</button>
    <button className="button outline" onClick={() => router.push("/dashboard")}>Voltar ao painel</button></div>
  </div>;

  if (!current) return <p>Não existem questões disponíveis nesta categoria.</p>;

  const isCorrect = chosen === current.correct_answer;
  return <div className="quiz-card">
    <div className="quiz-progress-head"><span>Questão {index + 1} de {quiz.length}</span><span><Clock3 size={16}/> Simulado</span></div>
    <div className="progress-line"><i style={{ width: `${((index + 1) / quiz.length) * 100}%` }}/></div>
    <h2>{current.statement}</h2>
    <div className="quiz-options">{current.options.map((option, i) => {
      let cls = "quiz-option";
      if (chosen !== null && i === current.correct_answer) cls += " correct";
      if (chosen === i && i !== current.correct_answer) cls += " wrong";
      return <button className={cls} key={i} onClick={() => answer(i)} disabled={chosen !== null}>
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
