"use client";

import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { AuthCard } from "@/components/auth-card";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const router = useRouter();
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(formData: FormData) {
    setLoading(true); setError("");
    const { error } = await createClient().auth.signInWithPassword({
      email: String(formData.get("email")),
      password: String(formData.get("password"))
    });
    if (error) { setError("E-mail ou senha inválidos."); setLoading(false); return; }
    router.replace("/dashboard"); router.refresh();
  }

  return <AuthCard title="Bem-vindo de volta!" subtitle="Acesse sua conta e continue estudando.">
    <form action={submit} className="auth-form">
      <label>E-mail<input name="email" type="email" required placeholder="voce@email.com"/></label>
      <label>Senha<input name="password" type="password" required minLength={6} placeholder="Sua senha"/></label>
      <div className="form-between"><span/><Link href="/esqueci-senha">Esqueci minha senha</Link></div>
      {error && <p className="form-error">{error}</p>}
      <button className="button primary wide" disabled={loading}>{loading ? "Entrando..." : "ENTRAR"}</button>
      <p className="form-foot">Ainda não possui conta? <Link href="/cadastro">Criar conta grátis</Link></p>
    </form>
  </AuthCard>;
}
