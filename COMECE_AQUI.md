# GUIA MAIS FÁCIL — ACADEMIA BOMBEIRO CIVIL

## Você fará somente 4 etapas

### 1. Criar um projeto no Supabase

Crie o projeto e espere ele terminar de preparar.

### 2. Colar um único SQL

Abra:

```text
SQL Editor → New query
```

Copie TODO o arquivo:

```text
SUPABASE_COLE_TUDO.sql
```

Cole e clique em **Run**.

Esse arquivo pode ser executado novamente sem gerar o erro de política duplicada.

No final, devem aparecer 50 questões para cada categoria.

### 3. Copiar somente duas informações

No Supabase, abra as configurações de API e copie:

- Project URL
- chave pública `anon`

Copie o arquivo `.env.pronto`, renomeie para `.env.local` e substitua apenas:

```env
NEXT_PUBLIC_SUPABASE_URL=https://COLE-AQUI-SEU-PROJETO.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=COLE-AQUI-SUA-CHAVE-ANON
```

Os demais dados já estão configurados:

```env
NEXT_PUBLIC_PIX_KEY=85994213560
NEXT_PUBLIC_PIX_HOLDER=Jonathan Francelino
NEXT_PUBLIC_WHATSAPP=5585994213560
```

### 4. Iniciar

No terminal da pasta:

```bash
npm install
npm run dev
```

Abra:

```text
http://localhost:3000
```

Crie sua conta com:

```text
jonathandesouzared@gmail.com
```

O sistema transformará esse e-mail automaticamente em administrador.

## Publicar depois

Quando o teste local estiver funcionando:

1. Envie a pasta ao GitHub.
2. Importe o projeto na Vercel.
3. Cadastre as seis variáveis.
4. Coloque a URL da Vercel no Supabase em Authentication → URL Configuration.

Não execute `001_schema.sql`, `002_questions.sql` ou `003_tornar_jonathan_admin.sql`.
Para esta versão, use apenas `SUPABASE_COLE_TUDO.sql`.
