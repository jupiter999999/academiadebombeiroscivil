"use client";

import { useState } from "react";
import { Copy, UploadCloud } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

export function PaymentForm() {
  const pixKey = process.env.NEXT_PUBLIC_PIX_KEY || "Configure sua chave Pix";
  const holder = process.env.NEXT_PUBLIC_PIX_HOLDER || "Titular não configurado";
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(formData: FormData) {
    setLoading(true); setMessage("");
    const file = formData.get("proof") as File;
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user || !file?.size) { setMessage("Selecione o comprovante."); setLoading(false); return; }

    const ext = file.name.split(".").pop() || "jpg";
    const path = `${user.id}/${crypto.randomUUID()}.${ext}`;
    const upload = await supabase.storage.from("payment-proofs").upload(path, file, { upsert: false });
    if (upload.error) { setMessage(upload.error.message); setLoading(false); return; }

    const result = await supabase.from("payment_requests").insert({
      user_id: user.id, amount: 15, proof_path: path, status: "pending"
    });
    setMessage(result.error ? result.error.message : "Comprovante enviado. Aguarde a aprovação do administrador.");
    setLoading(false);
  }

  return <div className="payment-grid">
    <article className="plan-card">
      <span className="eyebrow">PLANO MENSAL</span><h2>Academia Bombeiro Civil</h2>
      <div className="price"><strong>R$ 15</strong><span>/ mês</span></div>
      <ul><li>Acesso a todas as categorias</li><li>300 questões</li><li>Histórico e desempenho</li><li>Renovação por 30 dias</li></ul>
    </article>
    <article className="pix-card">
      <span className="eyebrow">PAGAMENTO VIA PIX</span><h2>Faça o pagamento</h2>
      <div className="pix-key"><div><small>CHAVE PIX</small><strong>{pixKey}</strong><span>{holder}</span></div>
      <button type="button" onClick={() => navigator.clipboard.writeText(pixKey)}><Copy/></button></div>
      <form action={submit} className="upload-form">
        <label className="upload-box"><UploadCloud/><strong>Enviar comprovante</strong><span>PNG, JPG ou PDF</span><input name="proof" type="file" accept="image/*,.pdf" required/></label>
        {message && <p className="form-success">{message}</p>}
        <button className="button primary wide" disabled={loading}>{loading ? "Enviando..." : "ENVIAR PARA APROVAÇÃO"}</button>
      </form>
    </article>
  </div>;
}
