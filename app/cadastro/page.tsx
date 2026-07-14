"use client";

import Link from "next/link";
import { useState } from "react";
import { AuthCard } from "@/components/auth-card";
import { createClient } from "@/lib/supabase/client";

export default function SignupPage() {
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(formData: FormData) {
    setLoading(true); setError(""); setMessage("");
    const password = String(formData.get("password"));
    const confirm = String(formData.get("confirm"));
    if (password !== confirm) { setError("As senhas não coincidem."); setLoading(false); return; }

    const { error } = await createClient().auth.signUp({
      email: String(formData.get("email")),
      password,
      options: {
        emailRedirectTo: `${location.origin}/auth/callback`,
        data: { full_name: String(formData.get("name")) }
      }
    });

    if (error) { setError(error.message); setLoading(false); return; }
    setMessage("Conta criada. Confira seu e-mail para confirmar o cadastro.");
    setLoading(false);
  }

  return <AuthCard title="Crie sua conta" subtitle="Teste a plataforma gratuitamente durante 24 horas.">
    <form action={submit} className="auth-form">
      <label>Nome completo<input name="name" required minLength={3} placeholder="Seu nome"/></label>
      <label>E-mail<input name="email" type="email" required placeholder="voce@email.com"/></label>
      <label>Senha<input name="password" type="password" required minLength={6} placeholder="Mínimo de 6 caracteres"/></label>
      <label>Confirmar senha<input name="confirm" type="password" required minLength={6}/></label>
      {error && <p className="form-error">{error}</p>}
      {message && <p className="form-success">{message}</p>}
      <button className="button primary wide" disabled={loading}>{loading ? "Criando..." : "CRIAR CONTA GRÁTIS"}</button>
      <p className="form-foot">Já possui conta? <Link href="/entrar">Entrar</Link></p>
    </form>
  </AuthCard>;
}
