import Link from "next/link";
import Image from "next/image";
import { ArrowRight, BarChart3, BookOpenCheck, CheckCircle2, MonitorSmartphone, ShieldCheck } from "lucide-react";
import { Logo } from "@/components/logo";

export default function HomePage() {
  return (
    <main className="landing">
      <section className="landing-hero">
        <Image src="/images/firefighter-bg.jpg" alt="" fill priority className="hero-image" />
        <div className="hero-shade" />
        <header className="landing-header">
          <Logo />
          <nav><Link href="/entrar">Entrar</Link><Link className="button primary" href="/cadastro">Criar conta grátis</Link></nav>
        </header>
        <div className="hero-content">
          <span className="eyebrow light">PLATAFORMA COMPLETA DE ESTUDOS</span>
          <h1>ESTUDE. PRATIQUE.<br/><em>EVOLUA. SALVE VIDAS.</em></h1>
          <p>Simulados organizados para Bombeiros Civis e profissionais de segurança. Crie sua conta e teste gratuitamente por 24 horas.</p>
          <div className="hero-features">
            <span><BookOpenCheck/> 300+ questões</span>
            <span><ShieldCheck/> 6 categorias</span>
            <span><BarChart3/> Desempenho detalhado</span>
          </div>
          <Link className="button primary large" href="/cadastro">COMEÇAR AGORA <ArrowRight size={19}/></Link>
        </div>
      </section>
      <section className="landing-benefits">
        <article><CheckCircle2/><div><h3>Questões organizadas</h3><p>Estude por categoria e revise seus erros.</p></div></article>
        <article><BarChart3/><div><h3>Simulados inteligentes</h3><p>Escolha 10, 20 ou 50 perguntas.</p></div></article>
        <article><MonitorSmartphone/><div><h3>Acesso multiplataforma</h3><p>Use no computador, tablet ou celular.</p></div></article>
      </section>
    </main>
  );
}
