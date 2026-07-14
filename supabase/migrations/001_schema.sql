-- Academia Bombeiro Civil - estrutura completa
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'Aluno',
  email text not null default '',
  role text not null default 'student' check (role in ('student','admin')),
  subscription_status text not null default 'trial' check (subscription_status in ('trial','active','expired','blocked')),
  trial_ends_at timestamptz not null default (now() + interval '24 hours'),
  access_ends_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('NR','NT','Extintores','Mapas','APH','Mangueiras')),
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
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  approved_at timestamptz,
  approved_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email, trial_ends_at)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
    coalesce(new.email,''),
    now() + interval '24 hours'
  );
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.has_platform_access()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid()
      and subscription_status <> 'blocked'
      and (role = 'admin' or trial_ends_at > now() or access_ends_at > now())
  );
$$;

create or replace function public.approve_payment(payment_id uuid, target_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  update public.payment_requests set status='approved', approved_at=now(), approved_by=auth.uid()
  where id=payment_id and user_id=target_user_id;
  update public.profiles set
    subscription_status='active',
    access_ends_at = greatest(coalesce(access_ends_at, now()), now()) + interval '30 days'
  where id=target_user_id;
end; $$;

create or replace function public.admin_set_user_status(target_user_id uuid, new_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  if new_status = 'active' then
    update public.profiles set subscription_status='active',
      access_ends_at=greatest(coalesce(access_ends_at,now()),now())+interval '30 days'
    where id=target_user_id;
  elsif new_status = 'blocked' then
    update public.profiles set subscription_status='blocked' where id=target_user_id;
  else raise exception 'Status inválido';
  end if;
end; $$;

alter table public.profiles enable row level security;
alter table public.questions enable row level security;
alter table public.attempts enable row level security;
alter table public.payment_requests enable row level security;

create policy "profile own or admin read" on public.profiles for select to authenticated
using (id=auth.uid() or public.is_admin());
create policy "admin update profiles" on public.profiles for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "questions accessible with subscription" on public.questions for select to authenticated
using (active=true and public.has_platform_access() or public.is_admin());
create policy "admin manages questions" on public.questions for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "attempt own read" on public.attempts for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "attempt own insert" on public.attempts for insert to authenticated with check (user_id=auth.uid() and public.has_platform_access());

create policy "payment own read" on public.payment_requests for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "payment own insert" on public.payment_requests for insert to authenticated with check (user_id=auth.uid());
create policy "admin manages payments" on public.payment_requests for update to authenticated using (public.is_admin()) with check (public.is_admin());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs','payment-proofs',true,5242880,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public=true;

create policy "users upload own proofs" on storage.objects for insert to authenticated
with check (bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "users and admins read proofs" on storage.objects for select to authenticated
using (bucket_id='payment-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- Depois de criar sua primeira conta, torne-a administradora:
-- update public.profiles set role='admin', subscription_status='active' where email='SEU_EMAIL@EXEMPLO.COM';
