import Link from "next/link";
import { Clock3, ShieldAlert } from "lucide-react";
import type { Profile } from "@/lib/types";

export function StatusBanner({ profile }: { profile: Profile }) {
  const now = Date.now();
  const trialEnd = new Date(profile.trial_ends_at).getTime();
  const accessEnd = profile.access_ends_at ? new Date(profile.access_ends_at).getTime() : 0;
  const hasAccess = profile.role === "admin" || trialEnd > now || accessEnd > now;

  if (!hasAccess || profile.subscription_status === "expired") {
    return (
      <div className="status-banner blocked">
        <ShieldAlert />
        <div><strong>Seu acesso está vencido.</strong><span>Renove por R$ 15 para continuar estudando.</span></div>
        <Link className="button primary small" href="/assinatura">Renovar acesso</Link>
      </div>
    );
  }

  if (profile.subscription_status === "trial") {
    const hours = Math.max(1, Math.ceil((trialEnd - now) / 3600000));
    return (
      <div className="status-banner trial">
        <Clock3 />
        <div><strong>Período gratuito ativo</strong><span>Restam aproximadamente {hours} hora(s).</span></div>
        <Link className="button outline small" href="/assinatura">Conhecer o plano</Link>
      </div>
    );
  }

  return null;
}
