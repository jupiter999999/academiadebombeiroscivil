# Academia Bombeiro Civil — instalação simplificada

Comece pelo arquivo `COMECE_AQUI.md`.

Para configurar o Supabase, execute somente `SUPABASE_COLE_TUDO.sql`.

# Academia Bombeiro Civil — versão profissional

Sistema em Next.js + Supabase com:

- cadastro e confirmação de e-mail;
- teste grátis por 24 horas;
- bloqueio após o teste;
- plano de R$ 15 por 30 dias;
- Pix manual e envio de comprovante;
- aprovação administrativa;
- painel do aluno;
- painel administrativo;
- 300 questões em seis categorias;
- histórico e desempenho;
- recuperação de senha;
- layout responsivo.

## 1. Instalação local

Instale o Node.js LTS e execute:

```bash
npm install
cp .env.example .env.local
npm run dev
```

Abra `http://localhost:3000`.

## 2. Criar o banco no Supabase

1. Crie um projeto no Supabase.
2. Abra **SQL Editor**.
3. Execute `supabase/migrations/001_schema.sql`.
4. Execute `supabase/seed/002_questions.sql`.
5. Em **Authentication > URL Configuration**, defina:
   - Site URL: `http://localhost:3000`
   - Redirect URL: `http://localhost:3000/auth/callback`
   - Depois da publicação, adicione também seu domínio da Vercel.
6. Copie a Project URL e a chave `anon` para `.env.local`.

## 3. Variáveis

Preencha:

```env
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
NEXT_PUBLIC_PIX_KEY=
NEXT_PUBLIC_PIX_HOLDER=
NEXT_PUBLIC_WHATSAPP=
NEXT_PUBLIC_SITE_URL=http://localhost:3000
```

Nunca use a chave `service_role` no navegador ou na Vercel para este projeto.

## 4. Criar administrador

Crie sua conta normalmente pelo site. Depois execute no SQL Editor:

```sql
update public.profiles
set role='admin', subscription_status='active',
    access_ends_at=now()+interval '10 years'
where email='SEU_EMAIL';
```

## 5. Publicar no GitHub

1. Crie um repositório vazio.
2. No terminal, dentro da pasta:

```bash
git init
git add .
git commit -m "Primeira versão"
git branch -M main
git remote add origin URL_DO_REPOSITORIO
git push -u origin main
```

## 6. Publicar na Vercel

1. Crie uma conta na Vercel usando o GitHub.
2. Clique em **Add New > Project**.
3. Importe o repositório.
4. Cadastre todas as variáveis do `.env.example`.
5. Clique em **Deploy**.
6. Copie o endereço gerado.
7. Adicione esse endereço nas URLs autorizadas do Supabase:
   - `https://SEU-PROJETO.vercel.app`
   - `https://SEU-PROJETO.vercel.app/auth/callback`
8. Atualize `NEXT_PUBLIC_SITE_URL` na Vercel.

## 7. Domínio próprio

Compre um domínio e, na Vercel, abra **Settings > Domains**. Adicione o domínio e siga os registros DNS mostrados.

## 8. Fluxo do cliente

1. Cria a conta.
2. Confirma o e-mail.
3. Usa a plataforma por 24 horas.
4. Após o vencimento, abre Assinatura.
5. Paga R$ 15 via Pix.
6. Envia o comprovante.
7. O administrador aprova.
8. O sistema libera 30 dias.

## Segurança

- Senhas são administradas pelo Supabase Auth.
- O banco usa Row Level Security.
- Alunos só consultam os próprios resultados.
- O painel administrativo exige `role = admin`.
- Nunca publique `.env.local`.
- Revise todas as questões com fontes oficiais antes de vender o conteúdo.

## Limitação desta primeira versão

O pagamento é conferido manualmente. A automação de Pix pode ser integrada posteriormente por Mercado Pago, Asaas ou outro gateway.


---

## Dados desta instalação

- Administrador: `jonathandesouzared@gmail.com`
- Pix: `85994213560`
- Titular: `Jonathan Francelino`
- WhatsApp: `5585994213560`

Use o arquivo `CONFIGURACAO_PRONTA.md` para seguir a instalação em ordem.
