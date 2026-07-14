"use client";
import { useState } from "react";
import { AuthCard } from "@/components/auth-card";
import { createClient } from "@/lib/supabase/client";

export default function ForgotPage() {
  const [message, setMessage] = useState("");
  async function submit(formData: FormData) {
    await createClient().auth.resetPasswordForEmail(String(formData.get("email")), {
      redirectTo: `${location.origin}/redefinir-senha`
    });
    setMessage("Se o e-mail estiver cadastrado, você receberá o link de recuperação.");
  }
  return <AuthCard title="Recuperar senha" subtitle="Informe o e-mail usado no cadastro.">
    <form action={submit} className="auth-form">
      <label>E-mail<input name="email" type="email" required/></label>
      {message && <p className="form-success">{message}</p>}
      <button className="button primary wide">ENVIAR LINK</button>
    </form>
  </AuthCard>;
}
