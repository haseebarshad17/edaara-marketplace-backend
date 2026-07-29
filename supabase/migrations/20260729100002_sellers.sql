-- 002_sellers.sql
-- One-time 2,000 PKR activation → unlimited listing

create table if not exists public.sellers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles (id) on delete cascade,
  shop_name text not null,
  shop_slug text unique,
  bio text,
  logo_url text,
  status text not null default 'draft'
    check (status in ('draft', 'pending_payment', 'active', 'suspended', 'rejected')),
  activation_fee_pkr integer not null default 2000,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists sellers_status_idx on public.sellers (status);
create index if not exists sellers_slug_idx on public.sellers (shop_slug);

drop trigger if exists sellers_set_updated_at on public.sellers;
create trigger sellers_set_updated_at
before update on public.sellers
for each row execute function public.set_updated_at();

alter table public.sellers enable row level security;

create policy "sellers_select_public_active"
  on public.sellers for select
  using (status = 'active' or auth.uid() = user_id);

create policy "sellers_insert_own"
  on public.sellers for insert
  with check (auth.uid() = user_id);

create policy "sellers_update_own"
  on public.sellers for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
