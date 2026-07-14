# CONFIGURAÇÃO PRONTA — ACADEMIA BOMBEIRO CIVIL

## Dados já configurados

- E-mail do administrador: `jonathandesouzared@gmail.com`
- Chave Pix: `85994213560`
- Titular do Pix: `Jonathan Francelino`
- WhatsApp: `5585994213560`
- Plano mensal: `R$ 15,00`
- Teste gratuito: `24 horas`
- Renovação aprovada: `30 dias`

## O que ainda precisa vir do Supabase

Depois de criar o projeto no Supabase, copie somente:

1. `Project URL`
2. Chave pública `anon`

Cole esses dois valores no arquivo `.env.local`.

## Ordem exata no Supabase

Abra **SQL Editor** e execute nesta ordem:

1. `supabase/migrations/001_schema.sql`
2. `supabase/seed/002_questions.sql`

Depois:

3. Crie sua conta no site usando `jonathandesouzared@gmail.com`
4. Confirme o e-mail recebido
5. Execute `supabase/003_tornar_jonathan_admin.sql`

## Criar o arquivo local de configuração

Copie:

```text
.env.pronto
```

Renomeie a cópia para:

```text
.env.local
```

Depois substitua apenas:

```env
NEXT_PUBLIC_SUPABASE_URL=https://COLE-AQUI-SEU-PROJETO.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=COLE-AQUI-SUA-CHAVE-ANON
```

## Testar

```bash
npm install
npm run dev
```

Abra:

```text
http://localhost:3000
```

## Publicar na Vercel

Na Vercel, cadastre estas variáveis:

```env
NEXT_PUBLIC_SUPABASE_URL=URL_DO_SUPABASE
NEXT_PUBLIC_SUPABASE_ANON_KEY=CHAVE_ANON_DO_SUPABASE
NEXT_PUBLIC_PIX_KEY=85994213560
NEXT_PUBLIC_PIX_HOLDER=Jonathan Francelino
NEXT_PUBLIC_WHATSAPP=5585994213560
NEXT_PUBLIC_SITE_URL=https://URL-FINAL-DA-VERCEL
```

## URLs no Supabase

Em **Authentication > URL Configuration**:

```text
Site URL:
https://URL-FINAL-DA-VERCEL

Redirect URLs:
https://URL-FINAL-DA-VERCEL/auth/callback
http://localhost:3000/auth/callback
```

## Importante

Não criei senha administrativa fixa dentro do código. A senha será escolhida por você no cadastro e guardada com segurança pelo Supabase Auth.
