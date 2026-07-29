-- 005: backfill profiles + helper so seller/profile flows never miss FK parent

-- Users who signed up before profiles table existed
insert into public.profiles (id, email, full_name)
select
  u.id,
  u.email,
  coalesce(u.raw_user_meta_data->>'full_name', split_part(coalesce(u.email, 'user'), '@', 1))
from auth.users u
on conflict (id) do nothing;

-- Allow authenticated users to insert their own profile row (idempotent self-heal)
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

-- RPC: ensure current user has a profile (call before seller/address writes)
create or replace function public.ensure_my_profile()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.profiles;
  auth_email text;
  auth_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select email, coalesce(raw_user_meta_data->>'full_name', split_part(coalesce(email, 'user'), '@', 1))
  into auth_email, auth_name
  from auth.users
  where id = auth.uid();

  insert into public.profiles (id, email, full_name)
  values (auth.uid(), auth_email, auth_name)
  on conflict (id) do update
    set email = excluded.email
  returning * into result;

  return result;
end;
$$;

revoke all on function public.ensure_my_profile() from public;
grant execute on function public.ensure_my_profile() to authenticated;
