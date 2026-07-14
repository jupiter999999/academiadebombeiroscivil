-- Execute este arquivo no SQL Editor do Supabase
-- SOMENTE depois de criar e confirmar a conta com o e-mail abaixo.

update public.profiles
set
  role = 'admin',
  subscription_status = 'active',
  access_ends_at = now() + interval '10 years'
where email = 'jonathandesouzared@gmail.com';

-- Conferência:
select id, full_name, email, role, subscription_status, access_ends_at
from public.profiles
where email = 'jonathandesouzared@gmail.com';
