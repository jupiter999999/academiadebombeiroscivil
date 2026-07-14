import { Logo } from "@/components/logo";
import Image from "next/image";
import type { ReactNode } from "react";

export function AuthCard({ children, title, subtitle }: { children: ReactNode; title: string; subtitle: string }) {
  return (
    <main className="auth-page">
      <section className="auth-form-panel">
        <Logo dark />
        <div className="auth-heading"><h1>{title}</h1><p>{subtitle}</p></div>
        {children}
      </section>
      <section className="auth-visual">
        <Image src="/images/firefighter-bg.jpg" alt="Bombeiro em operação" fill priority />
        <div className="auth-visual-shade"/>
        <blockquote>“Conhecimento, preparação e atitude salvam vidas.”</blockquote>
      </section>
    </main>
  );
}
