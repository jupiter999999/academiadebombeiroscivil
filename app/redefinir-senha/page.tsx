"use client";
import { useState } from "react";
import { AuthCard } from "@/components/auth-card";
import { createClient } from "@/lib/supabase/client";

export default function ResetPage() {
  const [message, setMessage] = useState("");
  async function submit(formData: FormData) {
    const password = String(formData.get("password"));
    const { error } = await createClient().auth.updateUser({ password });
    setMessage(error ? error.message : "Senha atualizada. Você já pode entrar.");
  }
  return <AuthCard title="Definir nova senha" subtitle="Cadastre uma senha segura para sua conta.">
    <form action={submit} className="auth-form">
      <label>Nova senha<input name="password" type="password" minLength={6} required/></label>
      {message && <p className="form-success">{message}</p>}
      <button className="button primary wide">SALVAR SENHA</button>
    </form>
  </AuthCard>;
}
