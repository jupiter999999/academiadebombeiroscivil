-- ============================================================
-- ACADEMIA BOMBEIRO CIVIL
-- INSTALAÇÃO COMPLETA E REEXECUTÁVEL NO SUPABASE
-- Pode executar este arquivo novamente sem erro de policy duplicada.
-- ============================================================

create extension if not exists pgcrypto;

-- 1) TABELAS
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'Aluno',
  email text not null default '',
  role text not null default 'student'
    check (role in ('student','admin')),
  subscription_status text not null default 'trial'
    check (subscription_status in ('trial','active','expired','blocked')),
  trial_ends_at timestamptz not null default (now() + interval '24 hours'),
  access_ends_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  category text not null
    check (category in ('NR','NT','Extintores','Mapas','APH','Mangueiras')),
  statement text not null,
  options jsonb not null,
  correct_answer integer not null check (correct_answer between 0 and 5),
  explanation text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null,
  total_questions integer not null,
  correct_answers integer not null,
  score_percent integer not null,
  created_at timestamptz not null default now()
);

create table if not exists public.payment_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(10,2) not null default 15,
  proof_path text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  approved_at timestamptz,
  approved_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

-- Impede duplicar perguntas ao executar novamente
create unique index if not exists questions_unique_statement
on public.questions (category, statement);

-- 2) PERFIL AUTOMÁTICO + ADMIN AUTOMÁTICO
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_role text;
  new_status text;
  new_access timestamptz;
begin
  if lower(coalesce(new.email,'')) = lower('jonathandesouzared@gmail.com') then
    new_role := 'admin';
    new_status := 'active';
    new_access := now() + interval '10 years';
  else
    new_role := 'student';
    new_status := 'trial';
    new_access := null;
  end if;

  insert into public.profiles (
    id, full_name, email, role, subscription_status, trial_ends_at, access_ends_at
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(coalesce(new.email,''),'@',1), 'Aluno'),
    coalesce(new.email,''),
    new_role,
    new_status,
    now() + interval '24 hours',
    new_access
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    email = excluded.email,
    role = case
      when lower(excluded.email) = lower('jonathandesouzared@gmail.com') then 'admin'
      else public.profiles.role
    end,
    subscription_status = case
      when lower(excluded.email) = lower('jonathandesouzared@gmail.com') then 'active'
      else public.profiles.subscription_status
    end,
    access_ends_at = case
      when lower(excluded.email) = lower('jonathandesouzared@gmail.com') then now() + interval '10 years'
      else public.profiles.access_ends_at
    end;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of email, raw_user_meta_data on auth.users
for each row execute procedure public.handle_new_user();

-- Corrige automaticamente o admin se a conta já existir
update public.profiles
set role='admin',
    subscription_status='active',
    access_ends_at=now()+interval '10 years'
where lower(email)=lower('jonathandesouzared@gmail.com');

-- 3) FUNÇÕES DE SEGURANÇA
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.has_platform_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.profiles
    where id = auth.uid()
      and subscription_status <> 'blocked'
      and (
        role = 'admin'
        or trial_ends_at > now()
        or access_ends_at > now()
      )
  );
$$;

create or replace function public.approve_payment(
  payment_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Acesso negado';
  end if;

  update public.payment_requests
  set status='approved',
      approved_at=now(),
      approved_by=auth.uid()
  where id=payment_id
    and user_id=target_user_id
    and status='pending';

  update public.profiles
  set subscription_status='active',
      access_ends_at =
        greatest(coalesce(access_ends_at, now()), now()) + interval '30 days'
  where id=target_user_id;
end;
$$;

create or replace function public.admin_set_user_status(
  target_user_id uuid,
  new_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Acesso negado';
  end if;

  if new_status = 'active' then
    update public.profiles
    set subscription_status='active',
        access_ends_at =
          greatest(coalesce(access_ends_at, now()), now()) + interval '30 days'
    where id=target_user_id;
  elsif new_status = 'blocked' then
    update public.profiles
    set subscription_status='blocked'
    where id=target_user_id;
  else
    raise exception 'Status inválido';
  end if;
end;
$$;

-- 4) RLS
alter table public.profiles enable row level security;
alter table public.questions enable row level security;
alter table public.attempts enable row level security;
alter table public.payment_requests enable row level security;

-- Remove políticas antigas antes de recriar
drop policy if exists "profile own or admin read" on public.profiles;
drop policy if exists "admin update profiles" on public.profiles;
drop policy if exists "questions accessible with subscription" on public.questions;
drop policy if exists "admin manages questions" on public.questions;
drop policy if exists "attempt own read" on public.attempts;
drop policy if exists "attempt own insert" on public.attempts;
drop policy if exists "payment own read" on public.payment_requests;
drop policy if exists "payment own insert" on public.payment_requests;
drop policy if exists "admin manages payments" on public.payment_requests;

create policy "profile own or admin read"
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin());

create policy "admin update profiles"
on public.profiles for update to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy "questions accessible with subscription"
on public.questions for select to authenticated
using (
  (active = true and public.has_platform_access())
  or public.is_admin()
);

create policy "admin manages questions"
on public.questions for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy "attempt own read"
on public.attempts for select to authenticated
using (user_id = auth.uid() or public.is_admin());

create policy "attempt own insert"
on public.attempts for insert to authenticated
with check (
  user_id = auth.uid()
  and public.has_platform_access()
);

create policy "payment own read"
on public.payment_requests for select to authenticated
using (user_id = auth.uid() or public.is_admin());

create policy "payment own insert"
on public.payment_requests for insert to authenticated
with check (user_id = auth.uid());

create policy "admin manages payments"
on public.payment_requests for update to authenticated
using (public.is_admin())
with check (public.is_admin());

-- 5) COMPROVANTES
insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'payment-proofs',
  'payment-proofs',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp','application/pdf']
)
on conflict (id) do update set
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types =
    array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists "users upload own proofs" on storage.objects;
drop policy if exists "users and admins read proofs" on storage.objects;

create policy "users upload own proofs"
on storage.objects for insert to authenticated
with check (
  bucket_id='payment-proofs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "users and admins read proofs"
on storage.objects for select to authenticated
using (
  bucket_id='payment-proofs'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

-- 6) QUESTÕES
insert into public.questions (
  category, statement, options, correct_answer, explanation
)
values
('NR', 'Qual é a finalidade geral das Normas Regulamentadoras (NRs)?', '["Definir apenas salários", "Estabelecer requisitos de segurança e saúde no trabalho", "Regular exclusivamente concursos públicos", "Substituir todas as leis trabalhistas"]'::jsonb, 1, 'As NRs estabelecem obrigações e medidas relacionadas à segurança e à saúde no trabalho.'),
('NR', 'Em uma atividade com risco ocupacional, qual atitude está mais alinhada às NRs?', '["Ignorar o risco se a tarefa for rápida", "Identificar perigos, avaliar riscos e adotar controles", "Usar somente placas de aviso", "Transferir toda responsabilidade ao trabalhador"]'::jsonb, 1, 'O gerenciamento preventivo envolve reconhecer perigos, avaliar riscos e aplicar medidas de controle.'),
('NR', 'O EPI deve ser considerado:', '["A única medida de prevenção possível", "Uma medida complementar dentro da hierarquia de controles", "Desnecessário quando há experiência", "Substituto automático do treinamento"]'::jsonb, 1, 'O EPI integra as medidas de prevenção, mas não substitui controles coletivos, procedimentos e treinamento.'),
('NR', 'Antes de executar uma tarefa não rotineira, é recomendável:', '["Começar rapidamente", "Avaliar os riscos e definir um procedimento seguro", "Retirar a sinalização", "Trabalhar sozinho obrigatoriamente"]'::jsonb, 1, 'Atividades não rotineiras exigem planejamento, análise dos riscos e definição de controles.'),
('NR', 'O trabalhador deve receber treinamento:', '["Somente após um acidente", "Quando necessário para executar a atividade com segurança", "Apenas se solicitar por escrito", "Somente quando usar uniforme"]'::jsonb, 1, 'Capacitação e orientação são partes essenciais da prevenção.'),
('NR', 'Uma condição de risco grave deve ser:', '["Ocultada para evitar atrasos", "Comunicada e tratada conforme os procedimentos de segurança", "Registrada somente no fim do mês", "Ignorada se ninguém se feriu"]'::jsonb, 1, 'Condições perigosas devem ser comunicadas e controladas.'),
('NR', 'A sinalização de segurança:', '["Substitui proteções físicas", "É uma medida de orientação e alerta, não substituindo outros controles", "Serve somente para visitantes", "Pode ser removida durante o trabalho"]'::jsonb, 1, 'Sinalização auxilia, mas não elimina a necessidade de controles técnicos e administrativos.'),
('NR', 'A proteção coletiva deve ser priorizada porque:', '["Protege somente o supervisor", "Pode proteger várias pessoas simultaneamente", "É sempre mais barata", "Dispensa manutenção"]'::jsonb, 1, 'Medidas coletivas atuam sobre a fonte ou o ambiente e podem proteger todos os expostos.'),
('NR', 'Um procedimento de emergência deve:', '["Ser conhecido apenas pela direção", "Ser definido, comunicado e treinado", "Ser improvisado durante o evento", "Conter apenas telefones"]'::jsonb, 1, 'Planos eficazes precisam ser conhecidos e praticados.'),
('NR', 'Ao encontrar um equipamento de proteção danificado, o correto é:', '["Continuar usando com cuidado", "Comunicar e providenciar substituição ou correção", "Emprestar a outro trabalhador", "Guardar sem informar"]'::jsonb, 1, 'Equipamentos danificados podem perder sua eficácia e devem ser retirados de uso.'),
('NR', 'Qual é a finalidade geral das Normas Regulamentadoras (NRs) em uma obra, antes de uma atividade em altura?', '["Definir apenas salários", "Estabelecer requisitos de segurança e saúde no trabalho", "Regular exclusivamente concursos públicos", "Substituir todas as leis trabalhistas"]'::jsonb, 1, 'As NRs estabelecem obrigações e medidas relacionadas à segurança e à saúde no trabalho.'),
('NR', 'Em uma atividade com risco ocupacional, qual atitude está mais alinhada às NRs em uma obra, antes de uma atividade em altura?', '["Ignorar o risco se a tarefa for rápida", "Identificar perigos, avaliar riscos e adotar controles", "Usar somente placas de aviso", "Transferir toda responsabilidade ao trabalhador"]'::jsonb, 1, 'O gerenciamento preventivo envolve reconhecer perigos, avaliar riscos e aplicar medidas de controle.'),
('NR', 'O EPI deve ser considerado em uma obra, antes de uma atividade em altura?', '["A única medida de prevenção possível", "Uma medida complementar dentro da hierarquia de controles", "Desnecessário quando há experiência", "Substituto automático do treinamento"]'::jsonb, 1, 'O EPI integra as medidas de prevenção, mas não substitui controles coletivos, procedimentos e treinamento.'),
('NR', 'Antes de executar uma tarefa não rotineira, é recomendável em uma obra, antes de uma atividade em altura?', '["Começar rapidamente", "Avaliar os riscos e definir um procedimento seguro", "Retirar a sinalização", "Trabalhar sozinho obrigatoriamente"]'::jsonb, 1, 'Atividades não rotineiras exigem planejamento, análise dos riscos e definição de controles.'),
('NR', 'O trabalhador deve receber treinamento em uma obra, antes de uma atividade em altura?', '["Somente após um acidente", "Quando necessário para executar a atividade com segurança", "Apenas se solicitar por escrito", "Somente quando usar uniforme"]'::jsonb, 1, 'Capacitação e orientação são partes essenciais da prevenção.'),
('NR', 'Uma condição de risco grave deve ser em uma obra, antes de uma atividade em altura?', '["Ocultada para evitar atrasos", "Comunicada e tratada conforme os procedimentos de segurança", "Registrada somente no fim do mês", "Ignorada se ninguém se feriu"]'::jsonb, 1, 'Condições perigosas devem ser comunicadas e controladas.'),
('NR', 'A sinalização de segurança em uma obra, antes de uma atividade em altura?', '["Substitui proteções físicas", "É uma medida de orientação e alerta, não substituindo outros controles", "Serve somente para visitantes", "Pode ser removida durante o trabalho"]'::jsonb, 1, 'Sinalização auxilia, mas não elimina a necessidade de controles técnicos e administrativos.'),
('NR', 'A proteção coletiva deve ser priorizada porque em uma obra, antes de uma atividade em altura?', '["Protege somente o supervisor", "Pode proteger várias pessoas simultaneamente", "É sempre mais barata", "Dispensa manutenção"]'::jsonb, 1, 'Medidas coletivas atuam sobre a fonte ou o ambiente e podem proteger todos os expostos.'),
('NR', 'Um procedimento de emergência deve em uma obra, antes de uma atividade em altura?', '["Ser conhecido apenas pela direção", "Ser definido, comunicado e treinado", "Ser improvisado durante o evento", "Conter apenas telefones"]'::jsonb, 1, 'Planos eficazes precisam ser conhecidos e praticados.'),
('NR', 'Ao encontrar um equipamento de proteção danificado, o correto é em uma obra, antes de uma atividade em altura?', '["Continuar usando com cuidado", "Comunicar e providenciar substituição ou correção", "Emprestar a outro trabalhador", "Guardar sem informar"]'::jsonb, 1, 'Equipamentos danificados podem perder sua eficácia e devem ser retirados de uso.'),
('NR', 'Qual é a finalidade geral das Normas Regulamentadoras (NRs) em uma indústria, durante uma manutenção?', '["Definir apenas salários", "Estabelecer requisitos de segurança e saúde no trabalho", "Regular exclusivamente concursos públicos", "Substituir todas as leis trabalhistas"]'::jsonb, 1, 'As NRs estabelecem obrigações e medidas relacionadas à segurança e à saúde no trabalho.'),
('NR', 'Em uma atividade com risco ocupacional, qual atitude está mais alinhada às NRs em uma indústria, durante uma manutenção?', '["Ignorar o risco se a tarefa for rápida", "Identificar perigos, avaliar riscos e adotar controles", "Usar somente placas de aviso", "Transferir toda responsabilidade ao trabalhador"]'::jsonb, 1, 'O gerenciamento preventivo envolve reconhecer perigos, avaliar riscos e aplicar medidas de controle.'),
('NR', 'O EPI deve ser considerado em uma indústria, durante uma manutenção?', '["A única medida de prevenção possível", "Uma medida complementar dentro da hierarquia de controles", "Desnecessário quando há experiência", "Substituto automático do treinamento"]'::jsonb, 1, 'O EPI integra as medidas de prevenção, mas não substitui controles coletivos, procedimentos e treinamento.'),
('NR', 'Antes de executar uma tarefa não rotineira, é recomendável em uma indústria, durante uma manutenção?', '["Começar rapidamente", "Avaliar os riscos e definir um procedimento seguro", "Retirar a sinalização", "Trabalhar sozinho obrigatoriamente"]'::jsonb, 1, 'Atividades não rotineiras exigem planejamento, análise dos riscos e definição de controles.'),
('NR', 'O trabalhador deve receber treinamento em uma indústria, durante uma manutenção?', '["Somente após um acidente", "Quando necessário para executar a atividade com segurança", "Apenas se solicitar por escrito", "Somente quando usar uniforme"]'::jsonb, 1, 'Capacitação e orientação são partes essenciais da prevenção.'),
('NR', 'Uma condição de risco grave deve ser em uma indústria, durante uma manutenção?', '["Ocultada para evitar atrasos", "Comunicada e tratada conforme os procedimentos de segurança", "Registrada somente no fim do mês", "Ignorada se ninguém se feriu"]'::jsonb, 1, 'Condições perigosas devem ser comunicadas e controladas.'),
('NR', 'A sinalização de segurança em uma indústria, durante uma manutenção?', '["Substitui proteções físicas", "É uma medida de orientação e alerta, não substituindo outros controles", "Serve somente para visitantes", "Pode ser removida durante o trabalho"]'::jsonb, 1, 'Sinalização auxilia, mas não elimina a necessidade de controles técnicos e administrativos.'),
('NR', 'A proteção coletiva deve ser priorizada porque em uma indústria, durante uma manutenção?', '["Protege somente o supervisor", "Pode proteger várias pessoas simultaneamente", "É sempre mais barata", "Dispensa manutenção"]'::jsonb, 1, 'Medidas coletivas atuam sobre a fonte ou o ambiente e podem proteger todos os expostos.'),
('NR', 'Um procedimento de emergência deve em uma indústria, durante uma manutenção?', '["Ser conhecido apenas pela direção", "Ser definido, comunicado e treinado", "Ser improvisado durante o evento", "Conter apenas telefones"]'::jsonb, 1, 'Planos eficazes precisam ser conhecidos e praticados.'),
('NR', 'Ao encontrar um equipamento de proteção danificado, o correto é em uma indústria, durante uma manutenção?', '["Continuar usando com cuidado", "Comunicar e providenciar substituição ou correção", "Emprestar a outro trabalhador", "Guardar sem informar"]'::jsonb, 1, 'Equipamentos danificados podem perder sua eficácia e devem ser retirados de uso.'),
('NR', 'Qual é a finalidade geral das Normas Regulamentadoras (NRs) em um depósito, ao movimentar materiais?', '["Definir apenas salários", "Estabelecer requisitos de segurança e saúde no trabalho", "Regular exclusivamente concursos públicos", "Substituir todas as leis trabalhistas"]'::jsonb, 1, 'As NRs estabelecem obrigações e medidas relacionadas à segurança e à saúde no trabalho.'),
('NR', 'Em uma atividade com risco ocupacional, qual atitude está mais alinhada às NRs em um depósito, ao movimentar materiais?', '["Ignorar o risco se a tarefa for rápida", "Identificar perigos, avaliar riscos e adotar controles", "Usar somente placas de aviso", "Transferir toda responsabilidade ao trabalhador"]'::jsonb, 1, 'O gerenciamento preventivo envolve reconhecer perigos, avaliar riscos e aplicar medidas de controle.'),
('NR', 'O EPI deve ser considerado em um depósito, ao movimentar materiais?', '["A única medida de prevenção possível", "Uma medida complementar dentro da hierarquia de controles", "Desnecessário quando há experiência", "Substituto automático do treinamento"]'::jsonb, 1, 'O EPI integra as medidas de prevenção, mas não substitui controles coletivos, procedimentos e treinamento.'),
('NR', 'Antes de executar uma tarefa não rotineira, é recomendável em um depósito, ao movimentar materiais?', '["Começar rapidamente", "Avaliar os riscos e definir um procedimento seguro", "Retirar a sinalização", "Trabalhar sozinho obrigatoriamente"]'::jsonb, 1, 'Atividades não rotineiras exigem planejamento, análise dos riscos e definição de controles.'),
('NR', 'O trabalhador deve receber treinamento em um depósito, ao movimentar materiais?', '["Somente após um acidente", "Quando necessário para executar a atividade com segurança", "Apenas se solicitar por escrito", "Somente quando usar uniforme"]'::jsonb, 1, 'Capacitação e orientação são partes essenciais da prevenção.'),
('NR', 'Uma condição de risco grave deve ser em um depósito, ao movimentar materiais?', '["Ocultada para evitar atrasos", "Comunicada e tratada conforme os procedimentos de segurança", "Registrada somente no fim do mês", "Ignorada se ninguém se feriu"]'::jsonb, 1, 'Condições perigosas devem ser comunicadas e controladas.'),
('NR', 'A sinalização de segurança em um depósito, ao movimentar materiais?', '["Substitui proteções físicas", "É uma medida de orientação e alerta, não substituindo outros controles", "Serve somente para visitantes", "Pode ser removida durante o trabalho"]'::jsonb, 1, 'Sinalização auxilia, mas não elimina a necessidade de controles técnicos e administrativos.'),
('NR', 'A proteção coletiva deve ser priorizada porque em um depósito, ao movimentar materiais?', '["Protege somente o supervisor", "Pode proteger várias pessoas simultaneamente", "É sempre mais barata", "Dispensa manutenção"]'::jsonb, 1, 'Medidas coletivas atuam sobre a fonte ou o ambiente e podem proteger todos os expostos.'),
('NR', 'Um procedimento de emergência deve em um depósito, ao movimentar materiais?', '["Ser conhecido apenas pela direção", "Ser definido, comunicado e treinado", "Ser improvisado durante o evento", "Conter apenas telefones"]'::jsonb, 1, 'Planos eficazes precisam ser conhecidos e praticados.'),
('NR', 'Ao encontrar um equipamento de proteção danificado, o correto é em um depósito, ao movimentar materiais?', '["Continuar usando com cuidado", "Comunicar e providenciar substituição ou correção", "Emprestar a outro trabalhador", "Guardar sem informar"]'::jsonb, 1, 'Equipamentos danificados podem perder sua eficácia e devem ser retirados de uso.'),
('NR', 'Qual é a finalidade geral das Normas Regulamentadoras (NRs) em uma cozinha industrial, ao operar equipamento?', '["Definir apenas salários", "Estabelecer requisitos de segurança e saúde no trabalho", "Regular exclusivamente concursos públicos", "Substituir todas as leis trabalhistas"]'::jsonb, 1, 'As NRs estabelecem obrigações e medidas relacionadas à segurança e à saúde no trabalho.'),
('NR', 'Em uma atividade com risco ocupacional, qual atitude está mais alinhada às NRs em uma cozinha industrial, ao operar equipamento?', '["Ignorar o risco se a tarefa for rápida", "Identificar perigos, avaliar riscos e adotar controles", "Usar somente placas de aviso", "Transferir toda responsabilidade ao trabalhador"]'::jsonb, 1, 'O gerenciamento preventivo envolve reconhecer perigos, avaliar riscos e aplicar medidas de controle.'),
('NR', 'O EPI deve ser considerado em uma cozinha industrial, ao operar equipamento?', '["A única medida de prevenção possível", "Uma medida complementar dentro da hierarquia de controles", "Desnecessário quando há experiência", "Substituto automático do treinamento"]'::jsonb, 1, 'O EPI integra as medidas de prevenção, mas não substitui controles coletivos, procedimentos e treinamento.'),
('NR', 'Antes de executar uma tarefa não rotineira, é recomendável em uma cozinha industrial, ao operar equipamento?', '["Começar rapidamente", "Avaliar os riscos e definir um procedimento seguro", "Retirar a sinalização", "Trabalhar sozinho obrigatoriamente"]'::jsonb, 1, 'Atividades não rotineiras exigem planejamento, análise dos riscos e definição de controles.'),
('NR', 'O trabalhador deve receber treinamento em uma cozinha industrial, ao operar equipamento?', '["Somente após um acidente", "Quando necessário para executar a atividade com segurança", "Apenas se solicitar por escrito", "Somente quando usar uniforme"]'::jsonb, 1, 'Capacitação e orientação são partes essenciais da prevenção.'),
('NR', 'Uma condição de risco grave deve ser em uma cozinha industrial, ao operar equipamento?', '["Ocultada para evitar atrasos", "Comunicada e tratada conforme os procedimentos de segurança", "Registrada somente no fim do mês", "Ignorada se ninguém se feriu"]'::jsonb, 1, 'Condições perigosas devem ser comunicadas e controladas.'),
('NR', 'A sinalização de segurança em uma cozinha industrial, ao operar equipamento?', '["Substitui proteções físicas", "É uma medida de orientação e alerta, não substituindo outros controles", "Serve somente para visitantes", "Pode ser removida durante o trabalho"]'::jsonb, 1, 'Sinalização auxilia, mas não elimina a necessidade de controles técnicos e administrativos.'),
('NR', 'A proteção coletiva deve ser priorizada porque em uma cozinha industrial, ao operar equipamento?', '["Protege somente o supervisor", "Pode proteger várias pessoas simultaneamente", "É sempre mais barata", "Dispensa manutenção"]'::jsonb, 1, 'Medidas coletivas atuam sobre a fonte ou o ambiente e podem proteger todos os expostos.'),
('NR', 'Um procedimento de emergência deve em uma cozinha industrial, ao operar equipamento?', '["Ser conhecido apenas pela direção", "Ser definido, comunicado e treinado", "Ser improvisado durante o evento", "Conter apenas telefones"]'::jsonb, 1, 'Planos eficazes precisam ser conhecidos e praticados.'),
('NR', 'Ao encontrar um equipamento de proteção danificado, o correto é em uma cozinha industrial, ao operar equipamento?', '["Continuar usando com cuidado", "Comunicar e providenciar substituição ou correção", "Emprestar a outro trabalhador", "Guardar sem informar"]'::jsonb, 1, 'Equipamentos danificados podem perder sua eficácia e devem ser retirados de uso.'),
('NT', 'Para estudar uma Norma Técnica do CBMCE, qual informação deve acompanhar a questão?', '["Somente o título informal", "Número, edição/ano e item de referência", "A opinião do instrutor", "A cor da capa"]'::jsonb, 1, 'A identificação da norma, versão e item permite conferir a fundamentação e evita usar texto revogado.'),
('NT', 'Antes de aplicar uma exigência de uma NT, deve-se:', '["Usar qualquer versão encontrada", "Conferir se a norma está vigente no portal oficial", "Confiar apenas em uma imagem", "Aplicar a versão mais antiga"]'::jsonb, 1, 'As normas podem ser atualizadas; a versão vigente deve ser consultada no portal oficial.'),
('NT', 'Em uma análise de segurança contra incêndio, a ocupação da edificação é importante porque:', '["Define apenas a pintura", "Influencia as medidas de segurança aplicáveis", "Elimina a necessidade de vistoria", "Serve apenas para cobrança"]'::jsonb, 1, 'O uso e a ocupação influenciam os riscos e as medidas exigidas.'),
('NT', 'As saídas de emergência devem ser analisadas considerando:', '["Somente a porta principal", "Caminhamento, capacidade, continuidade e desobstrução", "A decoração do ambiente", "A marca das fechaduras"]'::jsonb, 1, 'A rota precisa permitir abandono seguro e contínuo.'),
('NT', 'A documentação técnica deve representar:', '["Uma situação fictícia", "As condições e sistemas efetivamente previstos ou instalados", "Somente o mobiliário", "A preferência do proprietário"]'::jsonb, 1, 'Projetos e documentos devem corresponder às condições reais.'),
('NT', 'Uma medida de segurança instalada deve:', '["Ficar inacessível para evitar uso", "Permanecer identificada, acessível e em condições de operação", "Ser usada como depósito", "Ser ocultada pela decoração"]'::jsonb, 1, 'Equipamentos de emergência precisam estar disponíveis e operacionais.'),
('NT', 'Quando uma NT é revogada:', '["Suas questões continuam válidas para sempre", "O banco de questões deve ser revisado e atualizado", "Seu número pode ser reutilizado livremente", "Não é necessário avisar os alunos"]'::jsonb, 1, 'Questões vinculadas a textos revogados precisam de revisão.'),
('NT', 'Uma questão baseada em NT deve apresentar:', '["Apenas certo ou errado", "Explicação e referência verificável", "Somente a alternativa correta", "A opinião do autor"]'::jsonb, 1, 'A fundamentação melhora o aprendizado e permite auditoria.'),
('NT', 'Em uma vistoria, uma rota obstruída representa:', '["Uma melhoria estética", "Um possível comprometimento do abandono seguro", "Uma questão sem relevância", "Uma forma de sinalização"]'::jsonb, 1, 'Obstruções podem impedir ou retardar a evacuação.'),
('NT', 'O objetivo das medidas de segurança contra incêndio inclui:', '["Apenas proteger objetos", "Reduzir riscos à vida, ao patrimônio e ao meio ambiente", "Eliminar qualquer manutenção", "Substituir o treinamento"]'::jsonb, 1, 'A proteção contra incêndio busca prevenir, controlar e reduzir consequências.'),
('NT', 'Para estudar uma Norma Técnica do CBMCE, qual informação deve acompanhar a questão em uma edificação comercial?', '["Somente o título informal", "Número, edição/ano e item de referência", "A opinião do instrutor", "A cor da capa"]'::jsonb, 1, 'A identificação da norma, versão e item permite conferir a fundamentação e evita usar texto revogado.'),
('NT', 'Antes de aplicar uma exigência de uma NT, deve-se em uma edificação comercial?', '["Usar qualquer versão encontrada", "Conferir se a norma está vigente no portal oficial", "Confiar apenas em uma imagem", "Aplicar a versão mais antiga"]'::jsonb, 1, 'As normas podem ser atualizadas; a versão vigente deve ser consultada no portal oficial.'),
('NT', 'Em uma análise de segurança contra incêndio, a ocupação da edificação é importante porque em uma edificação comercial?', '["Define apenas a pintura", "Influencia as medidas de segurança aplicáveis", "Elimina a necessidade de vistoria", "Serve apenas para cobrança"]'::jsonb, 1, 'O uso e a ocupação influenciam os riscos e as medidas exigidas.'),
('NT', 'As saídas de emergência devem ser analisadas considerando em uma edificação comercial?', '["Somente a porta principal", "Caminhamento, capacidade, continuidade e desobstrução", "A decoração do ambiente", "A marca das fechaduras"]'::jsonb, 1, 'A rota precisa permitir abandono seguro e contínuo.'),
('NT', 'A documentação técnica deve representar em uma edificação comercial?', '["Uma situação fictícia", "As condições e sistemas efetivamente previstos ou instalados", "Somente o mobiliário", "A preferência do proprietário"]'::jsonb, 1, 'Projetos e documentos devem corresponder às condições reais.'),
('NT', 'Uma medida de segurança instalada deve em uma edificação comercial?', '["Ficar inacessível para evitar uso", "Permanecer identificada, acessível e em condições de operação", "Ser usada como depósito", "Ser ocultada pela decoração"]'::jsonb, 1, 'Equipamentos de emergência precisam estar disponíveis e operacionais.'),
('NT', 'Quando uma NT é revogada em uma edificação comercial?', '["Suas questões continuam válidas para sempre", "O banco de questões deve ser revisado e atualizado", "Seu número pode ser reutilizado livremente", "Não é necessário avisar os alunos"]'::jsonb, 1, 'Questões vinculadas a textos revogados precisam de revisão.'),
('NT', 'Uma questão baseada em NT deve apresentar em uma edificação comercial?', '["Apenas certo ou errado", "Explicação e referência verificável", "Somente a alternativa correta", "A opinião do autor"]'::jsonb, 1, 'A fundamentação melhora o aprendizado e permite auditoria.'),
('NT', 'Em uma vistoria, uma rota obstruída representa em uma edificação comercial?', '["Uma melhoria estética", "Um possível comprometimento do abandono seguro", "Uma questão sem relevância", "Uma forma de sinalização"]'::jsonb, 1, 'Obstruções podem impedir ou retardar a evacuação.'),
('NT', 'O objetivo das medidas de segurança contra incêndio inclui em uma edificação comercial?', '["Apenas proteger objetos", "Reduzir riscos à vida, ao patrimônio e ao meio ambiente", "Eliminar qualquer manutenção", "Substituir o treinamento"]'::jsonb, 1, 'A proteção contra incêndio busca prevenir, controlar e reduzir consequências.'),
('NT', 'Para estudar uma Norma Técnica do CBMCE, qual informação deve acompanhar a questão em uma escola?', '["Somente o título informal", "Número, edição/ano e item de referência", "A opinião do instrutor", "A cor da capa"]'::jsonb, 1, 'A identificação da norma, versão e item permite conferir a fundamentação e evita usar texto revogado.'),
('NT', 'Antes de aplicar uma exigência de uma NT, deve-se em uma escola?', '["Usar qualquer versão encontrada", "Conferir se a norma está vigente no portal oficial", "Confiar apenas em uma imagem", "Aplicar a versão mais antiga"]'::jsonb, 1, 'As normas podem ser atualizadas; a versão vigente deve ser consultada no portal oficial.'),
('NT', 'Em uma análise de segurança contra incêndio, a ocupação da edificação é importante porque em uma escola?', '["Define apenas a pintura", "Influencia as medidas de segurança aplicáveis", "Elimina a necessidade de vistoria", "Serve apenas para cobrança"]'::jsonb, 1, 'O uso e a ocupação influenciam os riscos e as medidas exigidas.'),
('NT', 'As saídas de emergência devem ser analisadas considerando em uma escola?', '["Somente a porta principal", "Caminhamento, capacidade, continuidade e desobstrução", "A decoração do ambiente", "A marca das fechaduras"]'::jsonb, 1, 'A rota precisa permitir abandono seguro e contínuo.'),
('NT', 'A documentação técnica deve representar em uma escola?', '["Uma situação fictícia", "As condições e sistemas efetivamente previstos ou instalados", "Somente o mobiliário", "A preferência do proprietário"]'::jsonb, 1, 'Projetos e documentos devem corresponder às condições reais.'),
('NT', 'Uma medida de segurança instalada deve em uma escola?', '["Ficar inacessível para evitar uso", "Permanecer identificada, acessível e em condições de operação", "Ser usada como depósito", "Ser ocultada pela decoração"]'::jsonb, 1, 'Equipamentos de emergência precisam estar disponíveis e operacionais.'),
('NT', 'Quando uma NT é revogada em uma escola?', '["Suas questões continuam válidas para sempre", "O banco de questões deve ser revisado e atualizado", "Seu número pode ser reutilizado livremente", "Não é necessário avisar os alunos"]'::jsonb, 1, 'Questões vinculadas a textos revogados precisam de revisão.'),
('NT', 'Uma questão baseada em NT deve apresentar em uma escola?', '["Apenas certo ou errado", "Explicação e referência verificável", "Somente a alternativa correta", "A opinião do autor"]'::jsonb, 1, 'A fundamentação melhora o aprendizado e permite auditoria.'),
('NT', 'Em uma vistoria, uma rota obstruída representa em uma escola?', '["Uma melhoria estética", "Um possível comprometimento do abandono seguro", "Uma questão sem relevância", "Uma forma de sinalização"]'::jsonb, 1, 'Obstruções podem impedir ou retardar a evacuação.'),
('NT', 'O objetivo das medidas de segurança contra incêndio inclui em uma escola?', '["Apenas proteger objetos", "Reduzir riscos à vida, ao patrimônio e ao meio ambiente", "Eliminar qualquer manutenção", "Substituir o treinamento"]'::jsonb, 1, 'A proteção contra incêndio busca prevenir, controlar e reduzir consequências.'),
('NT', 'Para estudar uma Norma Técnica do CBMCE, qual informação deve acompanhar a questão em um evento temporário?', '["Somente o título informal", "Número, edição/ano e item de referência", "A opinião do instrutor", "A cor da capa"]'::jsonb, 1, 'A identificação da norma, versão e item permite conferir a fundamentação e evita usar texto revogado.'),
('NT', 'Antes de aplicar uma exigência de uma NT, deve-se em um evento temporário?', '["Usar qualquer versão encontrada", "Conferir se a norma está vigente no portal oficial", "Confiar apenas em uma imagem", "Aplicar a versão mais antiga"]'::jsonb, 1, 'As normas podem ser atualizadas; a versão vigente deve ser consultada no portal oficial.'),
('NT', 'Em uma análise de segurança contra incêndio, a ocupação da edificação é importante porque em um evento temporário?', '["Define apenas a pintura", "Influencia as medidas de segurança aplicáveis", "Elimina a necessidade de vistoria", "Serve apenas para cobrança"]'::jsonb, 1, 'O uso e a ocupação influenciam os riscos e as medidas exigidas.'),
('NT', 'As saídas de emergência devem ser analisadas considerando em um evento temporário?', '["Somente a porta principal", "Caminhamento, capacidade, continuidade e desobstrução", "A decoração do ambiente", "A marca das fechaduras"]'::jsonb, 1, 'A rota precisa permitir abandono seguro e contínuo.'),
('NT', 'A documentação técnica deve representar em um evento temporário?', '["Uma situação fictícia", "As condições e sistemas efetivamente previstos ou instalados", "Somente o mobiliário", "A preferência do proprietário"]'::jsonb, 1, 'Projetos e documentos devem corresponder às condições reais.'),
('NT', 'Uma medida de segurança instalada deve em um evento temporário?', '["Ficar inacessível para evitar uso", "Permanecer identificada, acessível e em condições de operação", "Ser usada como depósito", "Ser ocultada pela decoração"]'::jsonb, 1, 'Equipamentos de emergência precisam estar disponíveis e operacionais.'),
('NT', 'Quando uma NT é revogada em um evento temporário?', '["Suas questões continuam válidas para sempre", "O banco de questões deve ser revisado e atualizado", "Seu número pode ser reutilizado livremente", "Não é necessário avisar os alunos"]'::jsonb, 1, 'Questões vinculadas a textos revogados precisam de revisão.'),
('NT', 'Uma questão baseada em NT deve apresentar em um evento temporário?', '["Apenas certo ou errado", "Explicação e referência verificável", "Somente a alternativa correta", "A opinião do autor"]'::jsonb, 1, 'A fundamentação melhora o aprendizado e permite auditoria.'),
('NT', 'Em uma vistoria, uma rota obstruída representa em um evento temporário?', '["Uma melhoria estética", "Um possível comprometimento do abandono seguro", "Uma questão sem relevância", "Uma forma de sinalização"]'::jsonb, 1, 'Obstruções podem impedir ou retardar a evacuação.'),
('NT', 'O objetivo das medidas de segurança contra incêndio inclui em um evento temporário?', '["Apenas proteger objetos", "Reduzir riscos à vida, ao patrimônio e ao meio ambiente", "Eliminar qualquer manutenção", "Substituir o treinamento"]'::jsonb, 1, 'A proteção contra incêndio busca prevenir, controlar e reduzir consequências.'),
('NT', 'Para estudar uma Norma Técnica do CBMCE, qual informação deve acompanhar a questão em um condomínio?', '["Somente o título informal", "Número, edição/ano e item de referência", "A opinião do instrutor", "A cor da capa"]'::jsonb, 1, 'A identificação da norma, versão e item permite conferir a fundamentação e evita usar texto revogado.'),
('NT', 'Antes de aplicar uma exigência de uma NT, deve-se em um condomínio?', '["Usar qualquer versão encontrada", "Conferir se a norma está vigente no portal oficial", "Confiar apenas em uma imagem", "Aplicar a versão mais antiga"]'::jsonb, 1, 'As normas podem ser atualizadas; a versão vigente deve ser consultada no portal oficial.'),
('NT', 'Em uma análise de segurança contra incêndio, a ocupação da edificação é importante porque em um condomínio?', '["Define apenas a pintura", "Influencia as medidas de segurança aplicáveis", "Elimina a necessidade de vistoria", "Serve apenas para cobrança"]'::jsonb, 1, 'O uso e a ocupação influenciam os riscos e as medidas exigidas.'),
('NT', 'As saídas de emergência devem ser analisadas considerando em um condomínio?', '["Somente a porta principal", "Caminhamento, capacidade, continuidade e desobstrução", "A decoração do ambiente", "A marca das fechaduras"]'::jsonb, 1, 'A rota precisa permitir abandono seguro e contínuo.'),
('NT', 'A documentação técnica deve representar em um condomínio?', '["Uma situação fictícia", "As condições e sistemas efetivamente previstos ou instalados", "Somente o mobiliário", "A preferência do proprietário"]'::jsonb, 1, 'Projetos e documentos devem corresponder às condições reais.'),
('NT', 'Uma medida de segurança instalada deve em um condomínio?', '["Ficar inacessível para evitar uso", "Permanecer identificada, acessível e em condições de operação", "Ser usada como depósito", "Ser ocultada pela decoração"]'::jsonb, 1, 'Equipamentos de emergência precisam estar disponíveis e operacionais.'),
('NT', 'Quando uma NT é revogada em um condomínio?', '["Suas questões continuam válidas para sempre", "O banco de questões deve ser revisado e atualizado", "Seu número pode ser reutilizado livremente", "Não é necessário avisar os alunos"]'::jsonb, 1, 'Questões vinculadas a textos revogados precisam de revisão.'),
('NT', 'Uma questão baseada em NT deve apresentar em um condomínio?', '["Apenas certo ou errado", "Explicação e referência verificável", "Somente a alternativa correta", "A opinião do autor"]'::jsonb, 1, 'A fundamentação melhora o aprendizado e permite auditoria.'),
('NT', 'Em uma vistoria, uma rota obstruída representa em um condomínio?', '["Uma melhoria estética", "Um possível comprometimento do abandono seguro", "Uma questão sem relevância", "Uma forma de sinalização"]'::jsonb, 1, 'Obstruções podem impedir ou retardar a evacuação.'),
('NT', 'O objetivo das medidas de segurança contra incêndio inclui em um condomínio?', '["Apenas proteger objetos", "Reduzir riscos à vida, ao patrimônio e ao meio ambiente", "Eliminar qualquer manutenção", "Substituir o treinamento"]'::jsonb, 1, 'A proteção contra incêndio busca prevenir, controlar e reduzir consequências.'),
('Extintores', 'Em um princípio de incêndio em equipamento elétrico energizado, qual agente é geralmente adequado?', '["Água em jato", "CO₂", "Água com mangueira de jardim", "Qualquer líquido"]'::jsonb, 1, 'O CO₂ não conduz eletricidade e não deixa resíduos; a situação deve ser avaliada com segurança.'),
('Extintores', 'Incêndios de classe A envolvem principalmente:', '["Materiais sólidos como papel, madeira e tecido", "Líquidos inflamáveis", "Metais combustíveis", "Óleos de cozinha"]'::jsonb, 0, 'Materiais classe A queimam em superfície e profundidade, geralmente deixando resíduos.'),
('Extintores', 'Incêndios de classe B envolvem principalmente:', '["Madeira", "Líquidos e gases inflamáveis", "Papel", "Tecidos"]'::jsonb, 1, 'A classe B está associada a líquidos inflamáveis, gases e materiais que queimam em superfície.'),
('Extintores', 'O jato do extintor deve ser dirigido preferencialmente:', '["À fumaça", "À base das chamas", "Ao teto", "Para trás do operador"]'::jsonb, 1, 'O agente deve atuar na zona de combustão, geralmente na base do fogo.'),
('Extintores', 'Antes de tentar combater um princípio de incêndio, deve-se:', '["Bloquear a própria saída", "Avaliar se há segurança e manter rota de fuga", "Entrar sozinho em local tomado por fumaça", "Aguardar o fogo crescer"]'::jsonb, 1, 'O combate inicial só deve ocorrer quando houver condições seguras e possibilidade de retirada.'),
('Extintores', 'Um extintor com acesso obstruído:', '["Continua plenamente disponível", "Pode ter seu uso atrasado em uma emergência", "Fica mais protegido", "Dispensa sinalização"]'::jsonb, 1, 'O acesso precisa permanecer livre.'),
('Extintores', 'O lacre rompido sem justificativa pode indicar:', '["Que o extintor está novo", "Necessidade de inspeção por pessoa competente", "Que a pressão aumentou", "Que não existe problema"]'::jsonb, 1, 'Alterações no lacre ou sinais de uso exigem verificação.'),
('Extintores', 'A inspeção visual deve observar:', '["Apenas a cor", "Acesso, integridade, sinalização e condições aparentes", "Somente o peso da parede", "A idade do prédio"]'::jsonb, 1, 'A inspeção visual identifica problemas que podem comprometer o uso.'),
('Extintores', 'Depois do uso, mesmo parcial, o extintor deve:', '["Voltar ao suporte normalmente", "Ser encaminhado para serviço adequado", "Ser completado com água", "Ser guardado em armário fechado"]'::jsonb, 1, 'O equipamento usado precisa de manutenção e recarga apropriadas.'),
('Extintores', 'A escolha do extintor depende principalmente:', '["Da cor da parede", "Da classe de fogo e dos riscos do ambiente", "Do tamanho do usuário", "Do horário"]'::jsonb, 1, 'O agente deve ser compatível com o combustível e o risco presente.'),
('Extintores', 'Em um princípio de incêndio em equipamento elétrico energizado, qual agente é geralmente adequado num galpão?', '["Água em jato", "CO₂", "Água com mangueira de jardim", "Qualquer líquido"]'::jsonb, 1, 'O CO₂ não conduz eletricidade e não deixa resíduos; a situação deve ser avaliada com segurança.'),
('Extintores', 'Incêndios de classe A envolvem principalmente num galpão?', '["Materiais sólidos como papel, madeira e tecido", "Líquidos inflamáveis", "Metais combustíveis", "Óleos de cozinha"]'::jsonb, 0, 'Materiais classe A queimam em superfície e profundidade, geralmente deixando resíduos.'),
('Extintores', 'Incêndios de classe B envolvem principalmente num galpão?', '["Madeira", "Líquidos e gases inflamáveis", "Papel", "Tecidos"]'::jsonb, 1, 'A classe B está associada a líquidos inflamáveis, gases e materiais que queimam em superfície.'),
('Extintores', 'O jato do extintor deve ser dirigido preferencialmente num galpão?', '["À fumaça", "À base das chamas", "Ao teto", "Para trás do operador"]'::jsonb, 1, 'O agente deve atuar na zona de combustão, geralmente na base do fogo.'),
('Extintores', 'Antes de tentar combater um princípio de incêndio, deve-se num galpão?', '["Bloquear a própria saída", "Avaliar se há segurança e manter rota de fuga", "Entrar sozinho em local tomado por fumaça", "Aguardar o fogo crescer"]'::jsonb, 1, 'O combate inicial só deve ocorrer quando houver condições seguras e possibilidade de retirada.'),
('Extintores', 'Um extintor com acesso obstruído num galpão?', '["Continua plenamente disponível", "Pode ter seu uso atrasado em uma emergência", "Fica mais protegido", "Dispensa sinalização"]'::jsonb, 1, 'O acesso precisa permanecer livre.'),
('Extintores', 'O lacre rompido sem justificativa pode indicar num galpão?', '["Que o extintor está novo", "Necessidade de inspeção por pessoa competente", "Que a pressão aumentou", "Que não existe problema"]'::jsonb, 1, 'Alterações no lacre ou sinais de uso exigem verificação.'),
('Extintores', 'A inspeção visual deve observar num galpão?', '["Apenas a cor", "Acesso, integridade, sinalização e condições aparentes", "Somente o peso da parede", "A idade do prédio"]'::jsonb, 1, 'A inspeção visual identifica problemas que podem comprometer o uso.'),
('Extintores', 'Depois do uso, mesmo parcial, o extintor deve num galpão?', '["Voltar ao suporte normalmente", "Ser encaminhado para serviço adequado", "Ser completado com água", "Ser guardado em armário fechado"]'::jsonb, 1, 'O equipamento usado precisa de manutenção e recarga apropriadas.'),
('Extintores', 'A escolha do extintor depende principalmente num galpão?', '["Da cor da parede", "Da classe de fogo e dos riscos do ambiente", "Do tamanho do usuário", "Do horário"]'::jsonb, 1, 'O agente deve ser compatível com o combustível e o risco presente.'),
('Extintores', 'Em um princípio de incêndio em equipamento elétrico energizado, qual agente é geralmente adequado num laboratório?', '["Água em jato", "CO₂", "Água com mangueira de jardim", "Qualquer líquido"]'::jsonb, 1, 'O CO₂ não conduz eletricidade e não deixa resíduos; a situação deve ser avaliada com segurança.'),
('Extintores', 'Incêndios de classe A envolvem principalmente num laboratório?', '["Materiais sólidos como papel, madeira e tecido", "Líquidos inflamáveis", "Metais combustíveis", "Óleos de cozinha"]'::jsonb, 0, 'Materiais classe A queimam em superfície e profundidade, geralmente deixando resíduos.'),
('Extintores', 'Incêndios de classe B envolvem principalmente num laboratório?', '["Madeira", "Líquidos e gases inflamáveis", "Papel", "Tecidos"]'::jsonb, 1, 'A classe B está associada a líquidos inflamáveis, gases e materiais que queimam em superfície.'),
('Extintores', 'O jato do extintor deve ser dirigido preferencialmente num laboratório?', '["À fumaça", "À base das chamas", "Ao teto", "Para trás do operador"]'::jsonb, 1, 'O agente deve atuar na zona de combustão, geralmente na base do fogo.'),
('Extintores', 'Antes de tentar combater um princípio de incêndio, deve-se num laboratório?', '["Bloquear a própria saída", "Avaliar se há segurança e manter rota de fuga", "Entrar sozinho em local tomado por fumaça", "Aguardar o fogo crescer"]'::jsonb, 1, 'O combate inicial só deve ocorrer quando houver condições seguras e possibilidade de retirada.'),
('Extintores', 'Um extintor com acesso obstruído num laboratório?', '["Continua plenamente disponível", "Pode ter seu uso atrasado em uma emergência", "Fica mais protegido", "Dispensa sinalização"]'::jsonb, 1, 'O acesso precisa permanecer livre.'),
('Extintores', 'O lacre rompido sem justificativa pode indicar num laboratório?', '["Que o extintor está novo", "Necessidade de inspeção por pessoa competente", "Que a pressão aumentou", "Que não existe problema"]'::jsonb, 1, 'Alterações no lacre ou sinais de uso exigem verificação.'),
('Extintores', 'A inspeção visual deve observar num laboratório?', '["Apenas a cor", "Acesso, integridade, sinalização e condições aparentes", "Somente o peso da parede", "A idade do prédio"]'::jsonb, 1, 'A inspeção visual identifica problemas que podem comprometer o uso.'),
('Extintores', 'Depois do uso, mesmo parcial, o extintor deve num laboratório?', '["Voltar ao suporte normalmente", "Ser encaminhado para serviço adequado", "Ser completado com água", "Ser guardado em armário fechado"]'::jsonb, 1, 'O equipamento usado precisa de manutenção e recarga apropriadas.'),
('Extintores', 'A escolha do extintor depende principalmente num laboratório?', '["Da cor da parede", "Da classe de fogo e dos riscos do ambiente", "Do tamanho do usuário", "Do horário"]'::jsonb, 1, 'O agente deve ser compatível com o combustível e o risco presente.'),
('Extintores', 'Em um princípio de incêndio em equipamento elétrico energizado, qual agente é geralmente adequado num veículo?', '["Água em jato", "CO₂", "Água com mangueira de jardim", "Qualquer líquido"]'::jsonb, 1, 'O CO₂ não conduz eletricidade e não deixa resíduos; a situação deve ser avaliada com segurança.'),
('Extintores', 'Incêndios de classe A envolvem principalmente num veículo?', '["Materiais sólidos como papel, madeira e tecido", "Líquidos inflamáveis", "Metais combustíveis", "Óleos de cozinha"]'::jsonb, 0, 'Materiais classe A queimam em superfície e profundidade, geralmente deixando resíduos.'),
('Extintores', 'Incêndios de classe B envolvem principalmente num veículo?', '["Madeira", "Líquidos e gases inflamáveis", "Papel", "Tecidos"]'::jsonb, 1, 'A classe B está associada a líquidos inflamáveis, gases e materiais que queimam em superfície.'),
('Extintores', 'O jato do extintor deve ser dirigido preferencialmente num veículo?', '["À fumaça", "À base das chamas", "Ao teto", "Para trás do operador"]'::jsonb, 1, 'O agente deve atuar na zona de combustão, geralmente na base do fogo.'),
('Extintores', 'Antes de tentar combater um princípio de incêndio, deve-se num veículo?', '["Bloquear a própria saída", "Avaliar se há segurança e manter rota de fuga", "Entrar sozinho em local tomado por fumaça", "Aguardar o fogo crescer"]'::jsonb, 1, 'O combate inicial só deve ocorrer quando houver condições seguras e possibilidade de retirada.'),
('Extintores', 'Um extintor com acesso obstruído num veículo?', '["Continua plenamente disponível", "Pode ter seu uso atrasado em uma emergência", "Fica mais protegido", "Dispensa sinalização"]'::jsonb, 1, 'O acesso precisa permanecer livre.'),
('Extintores', 'O lacre rompido sem justificativa pode indicar num veículo?', '["Que o extintor está novo", "Necessidade de inspeção por pessoa competente", "Que a pressão aumentou", "Que não existe problema"]'::jsonb, 1, 'Alterações no lacre ou sinais de uso exigem verificação.'),
('Extintores', 'A inspeção visual deve observar num veículo?', '["Apenas a cor", "Acesso, integridade, sinalização e condições aparentes", "Somente o peso da parede", "A idade do prédio"]'::jsonb, 1, 'A inspeção visual identifica problemas que podem comprometer o uso.'),
('Extintores', 'Depois do uso, mesmo parcial, o extintor deve num veículo?', '["Voltar ao suporte normalmente", "Ser encaminhado para serviço adequado", "Ser completado com água", "Ser guardado em armário fechado"]'::jsonb, 1, 'O equipamento usado precisa de manutenção e recarga apropriadas.'),
('Extintores', 'A escolha do extintor depende principalmente num veículo?', '["Da cor da parede", "Da classe de fogo e dos riscos do ambiente", "Do tamanho do usuário", "Do horário"]'::jsonb, 1, 'O agente deve ser compatível com o combustível e o risco presente.'),
('Extintores', 'Em um princípio de incêndio em equipamento elétrico energizado, qual agente é geralmente adequado num comércio?', '["Água em jato", "CO₂", "Água com mangueira de jardim", "Qualquer líquido"]'::jsonb, 1, 'O CO₂ não conduz eletricidade e não deixa resíduos; a situação deve ser avaliada com segurança.'),
('Extintores', 'Incêndios de classe A envolvem principalmente num comércio?', '["Materiais sólidos como papel, madeira e tecido", "Líquidos inflamáveis", "Metais combustíveis", "Óleos de cozinha"]'::jsonb, 0, 'Materiais classe A queimam em superfície e profundidade, geralmente deixando resíduos.'),
('Extintores', 'Incêndios de classe B envolvem principalmente num comércio?', '["Madeira", "Líquidos e gases inflamáveis", "Papel", "Tecidos"]'::jsonb, 1, 'A classe B está associada a líquidos inflamáveis, gases e materiais que queimam em superfície.'),
('Extintores', 'O jato do extintor deve ser dirigido preferencialmente num comércio?', '["À fumaça", "À base das chamas", "Ao teto", "Para trás do operador"]'::jsonb, 1, 'O agente deve atuar na zona de combustão, geralmente na base do fogo.'),
('Extintores', 'Antes de tentar combater um princípio de incêndio, deve-se num comércio?', '["Bloquear a própria saída", "Avaliar se há segurança e manter rota de fuga", "Entrar sozinho em local tomado por fumaça", "Aguardar o fogo crescer"]'::jsonb, 1, 'O combate inicial só deve ocorrer quando houver condições seguras e possibilidade de retirada.'),
('Extintores', 'Um extintor com acesso obstruído num comércio?', '["Continua plenamente disponível", "Pode ter seu uso atrasado em uma emergência", "Fica mais protegido", "Dispensa sinalização"]'::jsonb, 1, 'O acesso precisa permanecer livre.'),
('Extintores', 'O lacre rompido sem justificativa pode indicar num comércio?', '["Que o extintor está novo", "Necessidade de inspeção por pessoa competente", "Que a pressão aumentou", "Que não existe problema"]'::jsonb, 1, 'Alterações no lacre ou sinais de uso exigem verificação.'),
('Extintores', 'A inspeção visual deve observar num comércio?', '["Apenas a cor", "Acesso, integridade, sinalização e condições aparentes", "Somente o peso da parede", "A idade do prédio"]'::jsonb, 1, 'A inspeção visual identifica problemas que podem comprometer o uso.'),
('Extintores', 'Depois do uso, mesmo parcial, o extintor deve num comércio?', '["Voltar ao suporte normalmente", "Ser encaminhado para serviço adequado", "Ser completado com água", "Ser guardado em armário fechado"]'::jsonb, 1, 'O equipamento usado precisa de manutenção e recarga apropriadas.'),
('Extintores', 'A escolha do extintor depende principalmente num comércio?', '["Da cor da parede", "Da classe de fogo e dos riscos do ambiente", "Do tamanho do usuário", "Do horário"]'::jsonb, 1, 'O agente deve ser compatível com o combustível e o risco presente.'),
('Mapas', 'Em uma planta de emergência, a rota de fuga deve indicar:', '["O caminho seguro até uma saída", "A localização de objetos decorativos", "Apenas a entrada principal", "Somente áreas restritas"]'::jsonb, 0, 'O mapa deve orientar o ocupante até uma saída segura.'),
('Mapas', 'O símbolo ''Você está aqui'' serve para:', '["Indicar o autor do mapa", "Orientar a posição atual do usuário", "Mostrar o ponto mais perigoso", "Substituir todas as placas"]'::jsonb, 1, 'A referência de posição ajuda a interpretar o trajeto de abandono.'),
('Mapas', 'Uma rota desenhada atravessando uma área permanentemente bloqueada está:', '["Correta se for curta", "Inadequada", "Correta apenas à noite", "Melhor sinalizada"]'::jsonb, 1, 'A rota precisa corresponder a um caminho realmente disponível.'),
('Mapas', 'O ponto de encontro deve ficar:', '["Em local seguro, fora da área de risco", "Dentro da edificação", "Na frente da saída, bloqueando-a", "Próximo ao foco de incêndio"]'::jsonb, 0, 'O ponto deve permitir reunião e conferência sem exposição ou obstrução.'),
('Mapas', 'Em um mapa, os equipamentos de emergência devem:', '["Ser representados de forma clara e coerente", "Ser omitidos", "Aparecer apenas em texto pequeno", "Mudar de posição sem atualização"]'::jsonb, 0, 'Representação clara facilita localização durante a emergência.'),
('Mapas', 'Ao alterar o layout de um ambiente, o mapa de emergência deve:', '["Permanecer igual", "Ser revisado quando a alteração afetar rotas ou equipamentos", "Ser removido", "Mostrar apenas a planta antiga"]'::jsonb, 1, 'O mapa precisa refletir as condições atuais.'),
('Mapas', 'Uma boa planta de abandono deve ser:', '["Legível e instalada em ponto visível", "Complexa e sem legenda", "Guardada em uma gaveta", "Exibida somente na administração"]'::jsonb, 0, 'Legibilidade e visibilidade são essenciais.'),
('Mapas', 'Duas rotas convergindo para uma porta bloqueada indicam:', '["Redundância adequada", "Falha no planejamento ou na representação", "Maior segurança", "Ponto de encontro"]'::jsonb, 1, 'Rotas não podem depender de uma passagem indisponível.'),
('Mapas', 'A legenda de um mapa serve para:', '["Explicar o significado dos símbolos", "Informar preços", "Substituir o treinamento", "Esconder detalhes"]'::jsonb, 0, 'A legenda permite interpretar símbolos e cores.'),
('Mapas', 'A orientação do mapa deve facilitar:', '["A correspondência entre o desenho e o ambiente real", "A leitura somente por engenheiros", "A decoração da parede", "A alteração improvisada das rotas"]'::jsonb, 0, 'O usuário deve conseguir relacionar rapidamente planta e espaço físico.'),
('Mapas', 'Em uma planta de emergência, a rota de fuga deve indicar no mapa de um hotel?', '["O caminho seguro até uma saída", "A localização de objetos decorativos", "Apenas a entrada principal", "Somente áreas restritas"]'::jsonb, 0, 'O mapa deve orientar o ocupante até uma saída segura.'),
('Mapas', 'O símbolo ''Você está aqui'' serve para no mapa de um hotel?', '["Indicar o autor do mapa", "Orientar a posição atual do usuário", "Mostrar o ponto mais perigoso", "Substituir todas as placas"]'::jsonb, 1, 'A referência de posição ajuda a interpretar o trajeto de abandono.'),
('Mapas', 'Uma rota desenhada atravessando uma área permanentemente bloqueada está no mapa de um hotel?', '["Correta se for curta", "Inadequada", "Correta apenas à noite", "Melhor sinalizada"]'::jsonb, 1, 'A rota precisa corresponder a um caminho realmente disponível.'),
('Mapas', 'O ponto de encontro deve ficar no mapa de um hotel?', '["Em local seguro, fora da área de risco", "Dentro da edificação", "Na frente da saída, bloqueando-a", "Próximo ao foco de incêndio"]'::jsonb, 0, 'O ponto deve permitir reunião e conferência sem exposição ou obstrução.'),
('Mapas', 'Em um mapa, os equipamentos de emergência devem no mapa de um hotel?', '["Ser representados de forma clara e coerente", "Ser omitidos", "Aparecer apenas em texto pequeno", "Mudar de posição sem atualização"]'::jsonb, 0, 'Representação clara facilita localização durante a emergência.'),
('Mapas', 'Ao alterar o layout de um ambiente, o mapa de emergência deve no mapa de um hotel?', '["Permanecer igual", "Ser revisado quando a alteração afetar rotas ou equipamentos", "Ser removido", "Mostrar apenas a planta antiga"]'::jsonb, 1, 'O mapa precisa refletir as condições atuais.'),
('Mapas', 'Uma boa planta de abandono deve ser no mapa de um hotel?', '["Legível e instalada em ponto visível", "Complexa e sem legenda", "Guardada em uma gaveta", "Exibida somente na administração"]'::jsonb, 0, 'Legibilidade e visibilidade são essenciais.'),
('Mapas', 'Duas rotas convergindo para uma porta bloqueada indicam no mapa de um hotel?', '["Redundância adequada", "Falha no planejamento ou na representação", "Maior segurança", "Ponto de encontro"]'::jsonb, 1, 'Rotas não podem depender de uma passagem indisponível.'),
('Mapas', 'A legenda de um mapa serve para no mapa de um hotel?', '["Explicar o significado dos símbolos", "Informar preços", "Substituir o treinamento", "Esconder detalhes"]'::jsonb, 0, 'A legenda permite interpretar símbolos e cores.'),
('Mapas', 'A orientação do mapa deve facilitar no mapa de um hotel?', '["A correspondência entre o desenho e o ambiente real", "A leitura somente por engenheiros", "A decoração da parede", "A alteração improvisada das rotas"]'::jsonb, 0, 'O usuário deve conseguir relacionar rapidamente planta e espaço físico.'),
('Mapas', 'Em uma planta de emergência, a rota de fuga deve indicar no mapa de um hospital?', '["O caminho seguro até uma saída", "A localização de objetos decorativos", "Apenas a entrada principal", "Somente áreas restritas"]'::jsonb, 0, 'O mapa deve orientar o ocupante até uma saída segura.'),
('Mapas', 'O símbolo ''Você está aqui'' serve para no mapa de um hospital?', '["Indicar o autor do mapa", "Orientar a posição atual do usuário", "Mostrar o ponto mais perigoso", "Substituir todas as placas"]'::jsonb, 1, 'A referência de posição ajuda a interpretar o trajeto de abandono.'),
('Mapas', 'Uma rota desenhada atravessando uma área permanentemente bloqueada está no mapa de um hospital?', '["Correta se for curta", "Inadequada", "Correta apenas à noite", "Melhor sinalizada"]'::jsonb, 1, 'A rota precisa corresponder a um caminho realmente disponível.'),
('Mapas', 'O ponto de encontro deve ficar no mapa de um hospital?', '["Em local seguro, fora da área de risco", "Dentro da edificação", "Na frente da saída, bloqueando-a", "Próximo ao foco de incêndio"]'::jsonb, 0, 'O ponto deve permitir reunião e conferência sem exposição ou obstrução.'),
('Mapas', 'Em um mapa, os equipamentos de emergência devem no mapa de um hospital?', '["Ser representados de forma clara e coerente", "Ser omitidos", "Aparecer apenas em texto pequeno", "Mudar de posição sem atualização"]'::jsonb, 0, 'Representação clara facilita localização durante a emergência.'),
('Mapas', 'Ao alterar o layout de um ambiente, o mapa de emergência deve no mapa de um hospital?', '["Permanecer igual", "Ser revisado quando a alteração afetar rotas ou equipamentos", "Ser removido", "Mostrar apenas a planta antiga"]'::jsonb, 1, 'O mapa precisa refletir as condições atuais.'),
('Mapas', 'Uma boa planta de abandono deve ser no mapa de um hospital?', '["Legível e instalada em ponto visível", "Complexa e sem legenda", "Guardada em uma gaveta", "Exibida somente na administração"]'::jsonb, 0, 'Legibilidade e visibilidade são essenciais.'),
('Mapas', 'Duas rotas convergindo para uma porta bloqueada indicam no mapa de um hospital?', '["Redundância adequada", "Falha no planejamento ou na representação", "Maior segurança", "Ponto de encontro"]'::jsonb, 1, 'Rotas não podem depender de uma passagem indisponível.'),
('Mapas', 'A legenda de um mapa serve para no mapa de um hospital?', '["Explicar o significado dos símbolos", "Informar preços", "Substituir o treinamento", "Esconder detalhes"]'::jsonb, 0, 'A legenda permite interpretar símbolos e cores.'),
('Mapas', 'A orientação do mapa deve facilitar no mapa de um hospital?', '["A correspondência entre o desenho e o ambiente real", "A leitura somente por engenheiros", "A decoração da parede", "A alteração improvisada das rotas"]'::jsonb, 0, 'O usuário deve conseguir relacionar rapidamente planta e espaço físico.'),
('Mapas', 'Em uma planta de emergência, a rota de fuga deve indicar no mapa de um depósito?', '["O caminho seguro até uma saída", "A localização de objetos decorativos", "Apenas a entrada principal", "Somente áreas restritas"]'::jsonb, 0, 'O mapa deve orientar o ocupante até uma saída segura.'),
('Mapas', 'O símbolo ''Você está aqui'' serve para no mapa de um depósito?', '["Indicar o autor do mapa", "Orientar a posição atual do usuário", "Mostrar o ponto mais perigoso", "Substituir todas as placas"]'::jsonb, 1, 'A referência de posição ajuda a interpretar o trajeto de abandono.'),
('Mapas', 'Uma rota desenhada atravessando uma área permanentemente bloqueada está no mapa de um depósito?', '["Correta se for curta", "Inadequada", "Correta apenas à noite", "Melhor sinalizada"]'::jsonb, 1, 'A rota precisa corresponder a um caminho realmente disponível.'),
('Mapas', 'O ponto de encontro deve ficar no mapa de um depósito?', '["Em local seguro, fora da área de risco", "Dentro da edificação", "Na frente da saída, bloqueando-a", "Próximo ao foco de incêndio"]'::jsonb, 0, 'O ponto deve permitir reunião e conferência sem exposição ou obstrução.'),
('Mapas', 'Em um mapa, os equipamentos de emergência devem no mapa de um depósito?', '["Ser representados de forma clara e coerente", "Ser omitidos", "Aparecer apenas em texto pequeno", "Mudar de posição sem atualização"]'::jsonb, 0, 'Representação clara facilita localização durante a emergência.'),
('Mapas', 'Ao alterar o layout de um ambiente, o mapa de emergência deve no mapa de um depósito?', '["Permanecer igual", "Ser revisado quando a alteração afetar rotas ou equipamentos", "Ser removido", "Mostrar apenas a planta antiga"]'::jsonb, 1, 'O mapa precisa refletir as condições atuais.'),
('Mapas', 'Uma boa planta de abandono deve ser no mapa de um depósito?', '["Legível e instalada em ponto visível", "Complexa e sem legenda", "Guardada em uma gaveta", "Exibida somente na administração"]'::jsonb, 0, 'Legibilidade e visibilidade são essenciais.'),
('Mapas', 'Duas rotas convergindo para uma porta bloqueada indicam no mapa de um depósito?', '["Redundância adequada", "Falha no planejamento ou na representação", "Maior segurança", "Ponto de encontro"]'::jsonb, 1, 'Rotas não podem depender de uma passagem indisponível.'),
('Mapas', 'A legenda de um mapa serve para no mapa de um depósito?', '["Explicar o significado dos símbolos", "Informar preços", "Substituir o treinamento", "Esconder detalhes"]'::jsonb, 0, 'A legenda permite interpretar símbolos e cores.'),
('Mapas', 'A orientação do mapa deve facilitar no mapa de um depósito?', '["A correspondência entre o desenho e o ambiente real", "A leitura somente por engenheiros", "A decoração da parede", "A alteração improvisada das rotas"]'::jsonb, 0, 'O usuário deve conseguir relacionar rapidamente planta e espaço físico.'),
('Mapas', 'Em uma planta de emergência, a rota de fuga deve indicar no mapa de um auditório?', '["O caminho seguro até uma saída", "A localização de objetos decorativos", "Apenas a entrada principal", "Somente áreas restritas"]'::jsonb, 0, 'O mapa deve orientar o ocupante até uma saída segura.'),
('Mapas', 'O símbolo ''Você está aqui'' serve para no mapa de um auditório?', '["Indicar o autor do mapa", "Orientar a posição atual do usuário", "Mostrar o ponto mais perigoso", "Substituir todas as placas"]'::jsonb, 1, 'A referência de posição ajuda a interpretar o trajeto de abandono.'),
('Mapas', 'Uma rota desenhada atravessando uma área permanentemente bloqueada está no mapa de um auditório?', '["Correta se for curta", "Inadequada", "Correta apenas à noite", "Melhor sinalizada"]'::jsonb, 1, 'A rota precisa corresponder a um caminho realmente disponível.'),
('Mapas', 'O ponto de encontro deve ficar no mapa de um auditório?', '["Em local seguro, fora da área de risco", "Dentro da edificação", "Na frente da saída, bloqueando-a", "Próximo ao foco de incêndio"]'::jsonb, 0, 'O ponto deve permitir reunião e conferência sem exposição ou obstrução.'),
('Mapas', 'Em um mapa, os equipamentos de emergência devem no mapa de um auditório?', '["Ser representados de forma clara e coerente", "Ser omitidos", "Aparecer apenas em texto pequeno", "Mudar de posição sem atualização"]'::jsonb, 0, 'Representação clara facilita localização durante a emergência.'),
('Mapas', 'Ao alterar o layout de um ambiente, o mapa de emergência deve no mapa de um auditório?', '["Permanecer igual", "Ser revisado quando a alteração afetar rotas ou equipamentos", "Ser removido", "Mostrar apenas a planta antiga"]'::jsonb, 1, 'O mapa precisa refletir as condições atuais.'),
('Mapas', 'Uma boa planta de abandono deve ser no mapa de um auditório?', '["Legível e instalada em ponto visível", "Complexa e sem legenda", "Guardada em uma gaveta", "Exibida somente na administração"]'::jsonb, 0, 'Legibilidade e visibilidade são essenciais.'),
('Mapas', 'Duas rotas convergindo para uma porta bloqueada indicam no mapa de um auditório?', '["Redundância adequada", "Falha no planejamento ou na representação", "Maior segurança", "Ponto de encontro"]'::jsonb, 1, 'Rotas não podem depender de uma passagem indisponível.'),
('Mapas', 'A legenda de um mapa serve para no mapa de um auditório?', '["Explicar o significado dos símbolos", "Informar preços", "Substituir o treinamento", "Esconder detalhes"]'::jsonb, 0, 'A legenda permite interpretar símbolos e cores.'),
('Mapas', 'A orientação do mapa deve facilitar no mapa de um auditório?', '["A correspondência entre o desenho e o ambiente real", "A leitura somente por engenheiros", "A decoração da parede", "A alteração improvisada das rotas"]'::jsonb, 0, 'O usuário deve conseguir relacionar rapidamente planta e espaço físico.'),
('APH', 'Ao chegar a uma ocorrência de APH, a primeira preocupação deve ser:', '["A segurança da cena", "A coleta de documentos", "A remoção imediata de todos", "A fotografia do local"]'::jsonb, 0, 'Antes do contato, é necessário avaliar riscos para equipe, vítima e terceiros.'),
('APH', 'Em uma vítima inconsciente, a avaliação inicial inclui verificar:', '["Responsividade e respiração", "Apenas a temperatura", "Somente a pressão arterial", "A identidade completa"]'::jsonb, 0, 'A avaliação inicial identifica rapidamente ameaças imediatas à vida.'),
('APH', 'Uma vítima com suspeita de trauma deve ser movimentada:', '["Sem planejamento", "Somente quando necessário e com técnica adequada", "Puxando pelos braços", "Sempre sentada"]'::jsonb, 1, 'Movimentações desnecessárias podem agravar lesões.'),
('APH', 'Em hemorragia externa importante, uma medida inicial é:', '["Compressão direta conforme o protocolo e segurança", "Dar alimento", "Lavar continuamente sem avaliar", "Aguardar sem agir"]'::jsonb, 0, 'O controle rápido do sangramento é prioritário.'),
('APH', 'Durante o atendimento, o uso de luvas ajuda a:', '["Eliminar todos os riscos", "Reduzir exposição a fluidos biológicos", "Substituir a higiene das mãos", "Dispensar outros cuidados"]'::jsonb, 1, 'Luvas são uma barreira, mas integram um conjunto de precauções.'),
('APH', 'Uma pessoa em convulsão deve:', '["Ter objetos colocados na boca", "Ser protegida contra impactos e observada", "Ser imobilizada à força", "Receber água imediatamente"]'::jsonb, 1, 'Proteja a vítima e não introduza objetos na boca.'),
('APH', 'Em queimaduras térmicas recentes, deve-se evitar:', '["Remover a fonte de calor com segurança", "Aplicar substâncias caseiras sobre a lesão", "Acionar ajuda quando necessário", "Proteger a área"]'::jsonb, 1, 'Produtos caseiros podem agravar a lesão e dificultar a avaliação.'),
('APH', 'A comunicação com a central de emergência deve informar:', '["Local, natureza da ocorrência e condições observadas", "Apenas o nome do solicitante", "Somente a cor do veículo", "Informações não confirmadas como certeza"]'::jsonb, 0, 'Dados objetivos ajudam a dimensionar a resposta.'),
('APH', 'Na avaliação primária, alterações graves devem ser:', '["Deixadas para o final", "Identificadas e tratadas por prioridade", "Registradas apenas depois do transporte", "Ignoradas se a vítima fala"]'::jsonb, 1, 'A abordagem prioriza ameaças imediatas à vida.'),
('APH', 'Após prestar atendimento, é importante:', '["Não registrar nada", "Transmitir informações relevantes à equipe que dará continuidade", "Descartar materiais em qualquer lugar", "Divulgar imagens da vítima"]'::jsonb, 1, 'A passagem de informações assegura continuidade e segurança do cuidado.'),
('APH', 'Ao chegar a uma ocorrência de APH, a primeira preocupação deve ser em uma residência?', '["A segurança da cena", "A coleta de documentos", "A remoção imediata de todos", "A fotografia do local"]'::jsonb, 0, 'Antes do contato, é necessário avaliar riscos para equipe, vítima e terceiros.'),
('APH', 'Em uma vítima inconsciente, a avaliação inicial inclui verificar em uma residência?', '["Responsividade e respiração", "Apenas a temperatura", "Somente a pressão arterial", "A identidade completa"]'::jsonb, 0, 'A avaliação inicial identifica rapidamente ameaças imediatas à vida.'),
('APH', 'Uma vítima com suspeita de trauma deve ser movimentada em uma residência?', '["Sem planejamento", "Somente quando necessário e com técnica adequada", "Puxando pelos braços", "Sempre sentada"]'::jsonb, 1, 'Movimentações desnecessárias podem agravar lesões.'),
('APH', 'Em hemorragia externa importante, uma medida inicial é em uma residência?', '["Compressão direta conforme o protocolo e segurança", "Dar alimento", "Lavar continuamente sem avaliar", "Aguardar sem agir"]'::jsonb, 0, 'O controle rápido do sangramento é prioritário.'),
('APH', 'Durante o atendimento, o uso de luvas ajuda a em uma residência?', '["Eliminar todos os riscos", "Reduzir exposição a fluidos biológicos", "Substituir a higiene das mãos", "Dispensar outros cuidados"]'::jsonb, 1, 'Luvas são uma barreira, mas integram um conjunto de precauções.'),
('APH', 'Uma pessoa em convulsão deve em uma residência?', '["Ter objetos colocados na boca", "Ser protegida contra impactos e observada", "Ser imobilizada à força", "Receber água imediatamente"]'::jsonb, 1, 'Proteja a vítima e não introduza objetos na boca.'),
('APH', 'Em queimaduras térmicas recentes, deve-se evitar em uma residência?', '["Remover a fonte de calor com segurança", "Aplicar substâncias caseiras sobre a lesão", "Acionar ajuda quando necessário", "Proteger a área"]'::jsonb, 1, 'Produtos caseiros podem agravar a lesão e dificultar a avaliação.'),
('APH', 'A comunicação com a central de emergência deve informar em uma residência?', '["Local, natureza da ocorrência e condições observadas", "Apenas o nome do solicitante", "Somente a cor do veículo", "Informações não confirmadas como certeza"]'::jsonb, 0, 'Dados objetivos ajudam a dimensionar a resposta.'),
('APH', 'Na avaliação primária, alterações graves devem ser em uma residência?', '["Deixadas para o final", "Identificadas e tratadas por prioridade", "Registradas apenas depois do transporte", "Ignoradas se a vítima fala"]'::jsonb, 1, 'A abordagem prioriza ameaças imediatas à vida.'),
('APH', 'Após prestar atendimento, é importante em uma residência?', '["Não registrar nada", "Transmitir informações relevantes à equipe que dará continuidade", "Descartar materiais em qualquer lugar", "Divulgar imagens da vítima"]'::jsonb, 1, 'A passagem de informações assegura continuidade e segurança do cuidado.'),
('APH', 'Ao chegar a uma ocorrência de APH, a primeira preocupação deve ser num evento?', '["A segurança da cena", "A coleta de documentos", "A remoção imediata de todos", "A fotografia do local"]'::jsonb, 0, 'Antes do contato, é necessário avaliar riscos para equipe, vítima e terceiros.'),
('APH', 'Em uma vítima inconsciente, a avaliação inicial inclui verificar num evento?', '["Responsividade e respiração", "Apenas a temperatura", "Somente a pressão arterial", "A identidade completa"]'::jsonb, 0, 'A avaliação inicial identifica rapidamente ameaças imediatas à vida.'),
('APH', 'Uma vítima com suspeita de trauma deve ser movimentada num evento?', '["Sem planejamento", "Somente quando necessário e com técnica adequada", "Puxando pelos braços", "Sempre sentada"]'::jsonb, 1, 'Movimentações desnecessárias podem agravar lesões.'),
('APH', 'Em hemorragia externa importante, uma medida inicial é num evento?', '["Compressão direta conforme o protocolo e segurança", "Dar alimento", "Lavar continuamente sem avaliar", "Aguardar sem agir"]'::jsonb, 0, 'O controle rápido do sangramento é prioritário.'),
('APH', 'Durante o atendimento, o uso de luvas ajuda a num evento?', '["Eliminar todos os riscos", "Reduzir exposição a fluidos biológicos", "Substituir a higiene das mãos", "Dispensar outros cuidados"]'::jsonb, 1, 'Luvas são uma barreira, mas integram um conjunto de precauções.'),
('APH', 'Uma pessoa em convulsão deve num evento?', '["Ter objetos colocados na boca", "Ser protegida contra impactos e observada", "Ser imobilizada à força", "Receber água imediatamente"]'::jsonb, 1, 'Proteja a vítima e não introduza objetos na boca.'),
('APH', 'Em queimaduras térmicas recentes, deve-se evitar num evento?', '["Remover a fonte de calor com segurança", "Aplicar substâncias caseiras sobre a lesão", "Acionar ajuda quando necessário", "Proteger a área"]'::jsonb, 1, 'Produtos caseiros podem agravar a lesão e dificultar a avaliação.'),
('APH', 'A comunicação com a central de emergência deve informar num evento?', '["Local, natureza da ocorrência e condições observadas", "Apenas o nome do solicitante", "Somente a cor do veículo", "Informações não confirmadas como certeza"]'::jsonb, 0, 'Dados objetivos ajudam a dimensionar a resposta.'),
('APH', 'Na avaliação primária, alterações graves devem ser num evento?', '["Deixadas para o final", "Identificadas e tratadas por prioridade", "Registradas apenas depois do transporte", "Ignoradas se a vítima fala"]'::jsonb, 1, 'A abordagem prioriza ameaças imediatas à vida.'),
('APH', 'Após prestar atendimento, é importante num evento?', '["Não registrar nada", "Transmitir informações relevantes à equipe que dará continuidade", "Descartar materiais em qualquer lugar", "Divulgar imagens da vítima"]'::jsonb, 1, 'A passagem de informações assegura continuidade e segurança do cuidado.'),
('APH', 'Ao chegar a uma ocorrência de APH, a primeira preocupação deve ser em ambiente de trabalho?', '["A segurança da cena", "A coleta de documentos", "A remoção imediata de todos", "A fotografia do local"]'::jsonb, 0, 'Antes do contato, é necessário avaliar riscos para equipe, vítima e terceiros.'),
('APH', 'Em uma vítima inconsciente, a avaliação inicial inclui verificar em ambiente de trabalho?', '["Responsividade e respiração", "Apenas a temperatura", "Somente a pressão arterial", "A identidade completa"]'::jsonb, 0, 'A avaliação inicial identifica rapidamente ameaças imediatas à vida.'),
('APH', 'Uma vítima com suspeita de trauma deve ser movimentada em ambiente de trabalho?', '["Sem planejamento", "Somente quando necessário e com técnica adequada", "Puxando pelos braços", "Sempre sentada"]'::jsonb, 1, 'Movimentações desnecessárias podem agravar lesões.'),
('APH', 'Em hemorragia externa importante, uma medida inicial é em ambiente de trabalho?', '["Compressão direta conforme o protocolo e segurança", "Dar alimento", "Lavar continuamente sem avaliar", "Aguardar sem agir"]'::jsonb, 0, 'O controle rápido do sangramento é prioritário.'),
('APH', 'Durante o atendimento, o uso de luvas ajuda a em ambiente de trabalho?', '["Eliminar todos os riscos", "Reduzir exposição a fluidos biológicos", "Substituir a higiene das mãos", "Dispensar outros cuidados"]'::jsonb, 1, 'Luvas são uma barreira, mas integram um conjunto de precauções.'),
('APH', 'Uma pessoa em convulsão deve em ambiente de trabalho?', '["Ter objetos colocados na boca", "Ser protegida contra impactos e observada", "Ser imobilizada à força", "Receber água imediatamente"]'::jsonb, 1, 'Proteja a vítima e não introduza objetos na boca.'),
('APH', 'Em queimaduras térmicas recentes, deve-se evitar em ambiente de trabalho?', '["Remover a fonte de calor com segurança", "Aplicar substâncias caseiras sobre a lesão", "Acionar ajuda quando necessário", "Proteger a área"]'::jsonb, 1, 'Produtos caseiros podem agravar a lesão e dificultar a avaliação.'),
('APH', 'A comunicação com a central de emergência deve informar em ambiente de trabalho?', '["Local, natureza da ocorrência e condições observadas", "Apenas o nome do solicitante", "Somente a cor do veículo", "Informações não confirmadas como certeza"]'::jsonb, 0, 'Dados objetivos ajudam a dimensionar a resposta.'),
('APH', 'Na avaliação primária, alterações graves devem ser em ambiente de trabalho?', '["Deixadas para o final", "Identificadas e tratadas por prioridade", "Registradas apenas depois do transporte", "Ignoradas se a vítima fala"]'::jsonb, 1, 'A abordagem prioriza ameaças imediatas à vida.'),
('APH', 'Após prestar atendimento, é importante em ambiente de trabalho?', '["Não registrar nada", "Transmitir informações relevantes à equipe que dará continuidade", "Descartar materiais em qualquer lugar", "Divulgar imagens da vítima"]'::jsonb, 1, 'A passagem de informações assegura continuidade e segurança do cuidado.'),
('APH', 'Ao chegar a uma ocorrência de APH, a primeira preocupação deve ser em área remota?', '["A segurança da cena", "A coleta de documentos", "A remoção imediata de todos", "A fotografia do local"]'::jsonb, 0, 'Antes do contato, é necessário avaliar riscos para equipe, vítima e terceiros.'),
('APH', 'Em uma vítima inconsciente, a avaliação inicial inclui verificar em área remota?', '["Responsividade e respiração", "Apenas a temperatura", "Somente a pressão arterial", "A identidade completa"]'::jsonb, 0, 'A avaliação inicial identifica rapidamente ameaças imediatas à vida.'),
('APH', 'Uma vítima com suspeita de trauma deve ser movimentada em área remota?', '["Sem planejamento", "Somente quando necessário e com técnica adequada", "Puxando pelos braços", "Sempre sentada"]'::jsonb, 1, 'Movimentações desnecessárias podem agravar lesões.'),
('APH', 'Em hemorragia externa importante, uma medida inicial é em área remota?', '["Compressão direta conforme o protocolo e segurança", "Dar alimento", "Lavar continuamente sem avaliar", "Aguardar sem agir"]'::jsonb, 0, 'O controle rápido do sangramento é prioritário.'),
('APH', 'Durante o atendimento, o uso de luvas ajuda a em área remota?', '["Eliminar todos os riscos", "Reduzir exposição a fluidos biológicos", "Substituir a higiene das mãos", "Dispensar outros cuidados"]'::jsonb, 1, 'Luvas são uma barreira, mas integram um conjunto de precauções.'),
('APH', 'Uma pessoa em convulsão deve em área remota?', '["Ter objetos colocados na boca", "Ser protegida contra impactos e observada", "Ser imobilizada à força", "Receber água imediatamente"]'::jsonb, 1, 'Proteja a vítima e não introduza objetos na boca.'),
('APH', 'Em queimaduras térmicas recentes, deve-se evitar em área remota?', '["Remover a fonte de calor com segurança", "Aplicar substâncias caseiras sobre a lesão", "Acionar ajuda quando necessário", "Proteger a área"]'::jsonb, 1, 'Produtos caseiros podem agravar a lesão e dificultar a avaliação.'),
('APH', 'A comunicação com a central de emergência deve informar em área remota?', '["Local, natureza da ocorrência e condições observadas", "Apenas o nome do solicitante", "Somente a cor do veículo", "Informações não confirmadas como certeza"]'::jsonb, 0, 'Dados objetivos ajudam a dimensionar a resposta.'),
('APH', 'Na avaliação primária, alterações graves devem ser em área remota?', '["Deixadas para o final", "Identificadas e tratadas por prioridade", "Registradas apenas depois do transporte", "Ignoradas se a vítima fala"]'::jsonb, 1, 'A abordagem prioriza ameaças imediatas à vida.'),
('APH', 'Após prestar atendimento, é importante em área remota?', '["Não registrar nada", "Transmitir informações relevantes à equipe que dará continuidade", "Descartar materiais em qualquer lugar", "Divulgar imagens da vítima"]'::jsonb, 1, 'A passagem de informações assegura continuidade e segurança do cuidado.'),
('Mangueiras', 'Antes de utilizar uma mangueira de incêndio, deve-se verificar:', '["Integridade aparente e conexões", "Apenas a cor", "O nome do fabricante na parede", "Somente o comprimento visual"]'::jsonb, 0, 'Danos, conexões inadequadas ou obstruções podem comprometer a operação.'),
('Mangueiras', 'Uma mangueira armazenada de forma inadequada pode:', '["Ganhar pressão sozinha", "Sofrer danos e dificultar o uso", "Tornar-se incombustível", "Dispensar inspeção"]'::jsonb, 1, 'O armazenamento correto preserva o equipamento e facilita o emprego.'),
('Mangueiras', 'Ao pressurizar uma linha de mangueira, a equipe deve:', '["Manter comunicação e controle", "Ficar sobre a mangueira dobrada", "Soltar o esguicho", "Trabalhar sem coordenação"]'::jsonb, 0, 'Pressurização exige coordenação para evitar movimentos bruscos e acidentes.'),
('Mangueiras', 'Uma dobra acentuada na mangueira pode:', '["Melhorar a vazão", "Restringir o fluxo de água", "Aumentar o alcance", "Eliminar a pressão"]'::jsonb, 1, 'Estrangulamentos reduzem ou interrompem a passagem de água.'),
('Mangueiras', 'Após o uso, a mangueira deve ser:', '["Guardada molhada e suja", "Inspecionada, limpa e seca conforme o procedimento", "Abandonada pressurizada", "Exposta ao sol indefinidamente"]'::jsonb, 1, 'Cuidados pós-uso ajudam a evitar deterioração.'),
('Mangueiras', 'O esguicho na ponta da linha serve para:', '["Controlar e direcionar o fluxo", "Unir duas escadas", "Medir temperatura corporal", "Substituir a bomba"]'::jsonb, 0, 'O esguicho permite controlar a aplicação da água.'),
('Mangueiras', 'Durante o avanço com linha pressurizada, é importante:', '["Coordenar a equipe e proteger a rota de retirada", "Caminhar sem observar obstáculos", "Enrolar a mangueira nas pernas", "Fechar todas as comunicações"]'::jsonb, 0, 'Coordenação, equilíbrio e rota de segurança são essenciais.'),
('Mangueiras', 'Uma conexão mal acoplada pode:', '["Causar vazamento ou desacoplamento", "Aumentar sempre a pressão", "Melhorar a vedação automaticamente", "Não produzir qualquer efeito"]'::jsonb, 0, 'Acoplamentos devem estar corretamente unidos e verificados.'),
('Mangueiras', 'A inspeção periódica busca identificar:', '["Desgaste, danos e problemas nas conexões", "Somente sujeira externa", "A idade dos operadores", "A cor da água"]'::jsonb, 0, 'Inspeções detectam condições que comprometem a confiabilidade.'),
('Mangueiras', 'Ao movimentar uma mangueira em área com quinas, deve-se:', '["Ignorar o atrito", "Proteger a mangueira contra abrasão quando possível", "Aumentar todas as dobras", "Arrastar pelas conexões"]'::jsonb, 1, 'Abrasão e quinas podem danificar o revestimento.'),
('Mangueiras', 'Antes de utilizar uma mangueira de incêndio, deve-se verificar num treinamento?', '["Integridade aparente e conexões", "Apenas a cor", "O nome do fabricante na parede", "Somente o comprimento visual"]'::jsonb, 0, 'Danos, conexões inadequadas ou obstruções podem comprometer a operação.'),
('Mangueiras', 'Uma mangueira armazenada de forma inadequada pode num treinamento?', '["Ganhar pressão sozinha", "Sofrer danos e dificultar o uso", "Tornar-se incombustível", "Dispensar inspeção"]'::jsonb, 1, 'O armazenamento correto preserva o equipamento e facilita o emprego.'),
('Mangueiras', 'Ao pressurizar uma linha de mangueira, a equipe deve num treinamento?', '["Manter comunicação e controle", "Ficar sobre a mangueira dobrada", "Soltar o esguicho", "Trabalhar sem coordenação"]'::jsonb, 0, 'Pressurização exige coordenação para evitar movimentos bruscos e acidentes.'),
('Mangueiras', 'Uma dobra acentuada na mangueira pode num treinamento?', '["Melhorar a vazão", "Restringir o fluxo de água", "Aumentar o alcance", "Eliminar a pressão"]'::jsonb, 1, 'Estrangulamentos reduzem ou interrompem a passagem de água.'),
('Mangueiras', 'Após o uso, a mangueira deve ser num treinamento?', '["Guardada molhada e suja", "Inspecionada, limpa e seca conforme o procedimento", "Abandonada pressurizada", "Exposta ao sol indefinidamente"]'::jsonb, 1, 'Cuidados pós-uso ajudam a evitar deterioração.'),
('Mangueiras', 'O esguicho na ponta da linha serve para num treinamento?', '["Controlar e direcionar o fluxo", "Unir duas escadas", "Medir temperatura corporal", "Substituir a bomba"]'::jsonb, 0, 'O esguicho permite controlar a aplicação da água.'),
('Mangueiras', 'Durante o avanço com linha pressurizada, é importante num treinamento?', '["Coordenar a equipe e proteger a rota de retirada", "Caminhar sem observar obstáculos", "Enrolar a mangueira nas pernas", "Fechar todas as comunicações"]'::jsonb, 0, 'Coordenação, equilíbrio e rota de segurança são essenciais.'),
('Mangueiras', 'Uma conexão mal acoplada pode num treinamento?', '["Causar vazamento ou desacoplamento", "Aumentar sempre a pressão", "Melhorar a vedação automaticamente", "Não produzir qualquer efeito"]'::jsonb, 0, 'Acoplamentos devem estar corretamente unidos e verificados.'),
('Mangueiras', 'A inspeção periódica busca identificar num treinamento?', '["Desgaste, danos e problemas nas conexões", "Somente sujeira externa", "A idade dos operadores", "A cor da água"]'::jsonb, 0, 'Inspeções detectam condições que comprometem a confiabilidade.'),
('Mangueiras', 'Ao movimentar uma mangueira em área com quinas, deve-se num treinamento?', '["Ignorar o atrito", "Proteger a mangueira contra abrasão quando possível", "Aumentar todas as dobras", "Arrastar pelas conexões"]'::jsonb, 1, 'Abrasão e quinas podem danificar o revestimento.'),
('Mangueiras', 'Antes de utilizar uma mangueira de incêndio, deve-se verificar num combate inicial?', '["Integridade aparente e conexões", "Apenas a cor", "O nome do fabricante na parede", "Somente o comprimento visual"]'::jsonb, 0, 'Danos, conexões inadequadas ou obstruções podem comprometer a operação.'),
('Mangueiras', 'Uma mangueira armazenada de forma inadequada pode num combate inicial?', '["Ganhar pressão sozinha", "Sofrer danos e dificultar o uso", "Tornar-se incombustível", "Dispensar inspeção"]'::jsonb, 1, 'O armazenamento correto preserva o equipamento e facilita o emprego.'),
('Mangueiras', 'Ao pressurizar uma linha de mangueira, a equipe deve num combate inicial?', '["Manter comunicação e controle", "Ficar sobre a mangueira dobrada", "Soltar o esguicho", "Trabalhar sem coordenação"]'::jsonb, 0, 'Pressurização exige coordenação para evitar movimentos bruscos e acidentes.'),
('Mangueiras', 'Uma dobra acentuada na mangueira pode num combate inicial?', '["Melhorar a vazão", "Restringir o fluxo de água", "Aumentar o alcance", "Eliminar a pressão"]'::jsonb, 1, 'Estrangulamentos reduzem ou interrompem a passagem de água.'),
('Mangueiras', 'Após o uso, a mangueira deve ser num combate inicial?', '["Guardada molhada e suja", "Inspecionada, limpa e seca conforme o procedimento", "Abandonada pressurizada", "Exposta ao sol indefinidamente"]'::jsonb, 1, 'Cuidados pós-uso ajudam a evitar deterioração.'),
('Mangueiras', 'O esguicho na ponta da linha serve para num combate inicial?', '["Controlar e direcionar o fluxo", "Unir duas escadas", "Medir temperatura corporal", "Substituir a bomba"]'::jsonb, 0, 'O esguicho permite controlar a aplicação da água.'),
('Mangueiras', 'Durante o avanço com linha pressurizada, é importante num combate inicial?', '["Coordenar a equipe e proteger a rota de retirada", "Caminhar sem observar obstáculos", "Enrolar a mangueira nas pernas", "Fechar todas as comunicações"]'::jsonb, 0, 'Coordenação, equilíbrio e rota de segurança são essenciais.'),
('Mangueiras', 'Uma conexão mal acoplada pode num combate inicial?', '["Causar vazamento ou desacoplamento", "Aumentar sempre a pressão", "Melhorar a vedação automaticamente", "Não produzir qualquer efeito"]'::jsonb, 0, 'Acoplamentos devem estar corretamente unidos e verificados.'),
('Mangueiras', 'A inspeção periódica busca identificar num combate inicial?', '["Desgaste, danos e problemas nas conexões", "Somente sujeira externa", "A idade dos operadores", "A cor da água"]'::jsonb, 0, 'Inspeções detectam condições que comprometem a confiabilidade.'),
('Mangueiras', 'Ao movimentar uma mangueira em área com quinas, deve-se num combate inicial?', '["Ignorar o atrito", "Proteger a mangueira contra abrasão quando possível", "Aumentar todas as dobras", "Arrastar pelas conexões"]'::jsonb, 1, 'Abrasão e quinas podem danificar o revestimento.'),
('Mangueiras', 'Antes de utilizar uma mangueira de incêndio, deve-se verificar num galpão?', '["Integridade aparente e conexões", "Apenas a cor", "O nome do fabricante na parede", "Somente o comprimento visual"]'::jsonb, 0, 'Danos, conexões inadequadas ou obstruções podem comprometer a operação.'),
('Mangueiras', 'Uma mangueira armazenada de forma inadequada pode num galpão?', '["Ganhar pressão sozinha", "Sofrer danos e dificultar o uso", "Tornar-se incombustível", "Dispensar inspeção"]'::jsonb, 1, 'O armazenamento correto preserva o equipamento e facilita o emprego.'),
('Mangueiras', 'Ao pressurizar uma linha de mangueira, a equipe deve num galpão?', '["Manter comunicação e controle", "Ficar sobre a mangueira dobrada", "Soltar o esguicho", "Trabalhar sem coordenação"]'::jsonb, 0, 'Pressurização exige coordenação para evitar movimentos bruscos e acidentes.'),
('Mangueiras', 'Uma dobra acentuada na mangueira pode num galpão?', '["Melhorar a vazão", "Restringir o fluxo de água", "Aumentar o alcance", "Eliminar a pressão"]'::jsonb, 1, 'Estrangulamentos reduzem ou interrompem a passagem de água.'),
('Mangueiras', 'Após o uso, a mangueira deve ser num galpão?', '["Guardada molhada e suja", "Inspecionada, limpa e seca conforme o procedimento", "Abandonada pressurizada", "Exposta ao sol indefinidamente"]'::jsonb, 1, 'Cuidados pós-uso ajudam a evitar deterioração.'),
('Mangueiras', 'O esguicho na ponta da linha serve para num galpão?', '["Controlar e direcionar o fluxo", "Unir duas escadas", "Medir temperatura corporal", "Substituir a bomba"]'::jsonb, 0, 'O esguicho permite controlar a aplicação da água.'),
('Mangueiras', 'Durante o avanço com linha pressurizada, é importante num galpão?', '["Coordenar a equipe e proteger a rota de retirada", "Caminhar sem observar obstáculos", "Enrolar a mangueira nas pernas", "Fechar todas as comunicações"]'::jsonb, 0, 'Coordenação, equilíbrio e rota de segurança são essenciais.'),
('Mangueiras', 'Uma conexão mal acoplada pode num galpão?', '["Causar vazamento ou desacoplamento", "Aumentar sempre a pressão", "Melhorar a vedação automaticamente", "Não produzir qualquer efeito"]'::jsonb, 0, 'Acoplamentos devem estar corretamente unidos e verificados.'),
('Mangueiras', 'A inspeção periódica busca identificar num galpão?', '["Desgaste, danos e problemas nas conexões", "Somente sujeira externa", "A idade dos operadores", "A cor da água"]'::jsonb, 0, 'Inspeções detectam condições que comprometem a confiabilidade.'),
('Mangueiras', 'Ao movimentar uma mangueira em área com quinas, deve-se num galpão?', '["Ignorar o atrito", "Proteger a mangueira contra abrasão quando possível", "Aumentar todas as dobras", "Arrastar pelas conexões"]'::jsonb, 1, 'Abrasão e quinas podem danificar o revestimento.'),
('Mangueiras', 'Antes de utilizar uma mangueira de incêndio, deve-se verificar num pátio industrial?', '["Integridade aparente e conexões", "Apenas a cor", "O nome do fabricante na parede", "Somente o comprimento visual"]'::jsonb, 0, 'Danos, conexões inadequadas ou obstruções podem comprometer a operação.'),
('Mangueiras', 'Uma mangueira armazenada de forma inadequada pode num pátio industrial?', '["Ganhar pressão sozinha", "Sofrer danos e dificultar o uso", "Tornar-se incombustível", "Dispensar inspeção"]'::jsonb, 1, 'O armazenamento correto preserva o equipamento e facilita o emprego.'),
('Mangueiras', 'Ao pressurizar uma linha de mangueira, a equipe deve num pátio industrial?', '["Manter comunicação e controle", "Ficar sobre a mangueira dobrada", "Soltar o esguicho", "Trabalhar sem coordenação"]'::jsonb, 0, 'Pressurização exige coordenação para evitar movimentos bruscos e acidentes.'),
('Mangueiras', 'Uma dobra acentuada na mangueira pode num pátio industrial?', '["Melhorar a vazão", "Restringir o fluxo de água", "Aumentar o alcance", "Eliminar a pressão"]'::jsonb, 1, 'Estrangulamentos reduzem ou interrompem a passagem de água.'),
('Mangueiras', 'Após o uso, a mangueira deve ser num pátio industrial?', '["Guardada molhada e suja", "Inspecionada, limpa e seca conforme o procedimento", "Abandonada pressurizada", "Exposta ao sol indefinidamente"]'::jsonb, 1, 'Cuidados pós-uso ajudam a evitar deterioração.'),
('Mangueiras', 'O esguicho na ponta da linha serve para num pátio industrial?', '["Controlar e direcionar o fluxo", "Unir duas escadas", "Medir temperatura corporal", "Substituir a bomba"]'::jsonb, 0, 'O esguicho permite controlar a aplicação da água.'),
('Mangueiras', 'Durante o avanço com linha pressurizada, é importante num pátio industrial?', '["Coordenar a equipe e proteger a rota de retirada", "Caminhar sem observar obstáculos", "Enrolar a mangueira nas pernas", "Fechar todas as comunicações"]'::jsonb, 0, 'Coordenação, equilíbrio e rota de segurança são essenciais.'),
('Mangueiras', 'Uma conexão mal acoplada pode num pátio industrial?', '["Causar vazamento ou desacoplamento", "Aumentar sempre a pressão", "Melhorar a vedação automaticamente", "Não produzir qualquer efeito"]'::jsonb, 0, 'Acoplamentos devem estar corretamente unidos e verificados.'),
('Mangueiras', 'A inspeção periódica busca identificar num pátio industrial?', '["Desgaste, danos e problemas nas conexões", "Somente sujeira externa", "A idade dos operadores", "A cor da água"]'::jsonb, 0, 'Inspeções detectam condições que comprometem a confiabilidade.'),
('Mangueiras', 'Ao movimentar uma mangueira em área com quinas, deve-se num pátio industrial?', '["Ignorar o atrito", "Proteger a mangueira contra abrasão quando possível", "Aumentar todas as dobras", "Arrastar pelas conexões"]'::jsonb, 1, 'Abrasão e quinas podem danificar o revestimento.')
on conflict (category, statement) do update set
  options = excluded.options,
  correct_answer = excluded.correct_answer,
  explanation = excluded.explanation,
  active = true;

-- 7) RESULTADO DA INSTALAÇÃO
select
  category,
  count(*) as quantidade
from public.questions
group by category
order by category;
