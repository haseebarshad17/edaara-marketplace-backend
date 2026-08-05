-- =============================================================================
-- APPLY ALL MARKETPLACE MIGRATIONS (run once in Supabase SQL Editor)
-- Project: iycmjqhfxzyqaxljiupz
-- Dashboard → SQL → New query → paste this entire file → Run
-- =============================================================================

-- 001_profiles.sql
create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  role text not null default 'buyer'
    check (role in ('buyer', 'seller', 'admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists profiles_email_idx on public.profiles (email);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

create table if not exists public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  label text default 'Home',
  full_name text not null,
  phone text not null,
  line1 text not null,
  line2 text,
  city text not null,
  province text,
  postal_code text,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists addresses_user_id_idx on public.addresses (user_id);

alter table public.addresses enable row level security;

drop policy if exists "addresses_all_own" on public.addresses;
create policy "addresses_all_own"
  on public.addresses for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Backfill profiles for users who signed up before this migration
insert into public.profiles (id, email, full_name)
select
  u.id,
  u.email,
  coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1))
from auth.users u
on conflict (id) do nothing;

-- 002_sellers.sql
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

drop policy if exists "sellers_select_public_active" on public.sellers;
create policy "sellers_select_public_active"
  on public.sellers for select
  using (status = 'active' or auth.uid() = user_id);

drop policy if exists "sellers_insert_own" on public.sellers;
create policy "sellers_insert_own"
  on public.sellers for insert
  with check (auth.uid() = user_id);

drop policy if exists "sellers_update_own" on public.sellers;
create policy "sellers_update_own"
  on public.sellers for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 003_catalog.sql
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  image_url text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.sellers (id) on delete cascade,
  title text not null,
  slug text not null,
  description text,
  price_pkr integer not null check (price_pkr >= 0),
  compare_at_pkr integer check (compare_at_pkr is null or compare_at_pkr >= price_pkr),
  stock integer not null default 0 check (stock >= 0),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'archived')),
  category_slug text references public.categories (slug) on delete set null,
  cover_image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (seller_id, slug)
);

create index if not exists products_seller_id_idx on public.products (seller_id);
create index if not exists products_status_idx on public.products (status);
create index if not exists products_category_slug_idx on public.products (category_slug);

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  url text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists product_images_product_id_idx on public.product_images (product_id);

alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;

drop policy if exists "categories_select_all" on public.categories;
create policy "categories_select_all"
  on public.categories for select
  using (true);

drop policy if exists "products_select_active_or_owner" on public.products;
create policy "products_select_active_or_owner"
  on public.products for select
  using (
    status = 'active'
    or exists (
      select 1 from public.sellers s
      where s.id = products.seller_id and s.user_id = auth.uid()
    )
  );

drop policy if exists "products_write_own_active_seller" on public.products;
create policy "products_write_own_active_seller"
  on public.products for all
  using (
    exists (
      select 1 from public.sellers s
      where s.id = products.seller_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  )
  with check (
    exists (
      select 1 from public.sellers s
      where s.id = products.seller_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  );

drop policy if exists "product_images_select_via_product" on public.product_images;
create policy "product_images_select_via_product"
  on public.product_images for select
  using (
    exists (
      select 1 from public.products p
      where p.id = product_images.product_id
        and (
          p.status = 'active'
          or exists (
            select 1 from public.sellers s
            where s.id = p.seller_id and s.user_id = auth.uid()
          )
        )
    )
  );

drop policy if exists "product_images_write_own" on public.product_images;
create policy "product_images_write_own"
  on public.product_images for all
  using (
    exists (
      select 1 from public.products p
      join public.sellers s on s.id = p.seller_id
      where p.id = product_images.product_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  )
  with check (
    exists (
      select 1 from public.products p
      join public.sellers s on s.id = p.seller_id
      where p.id = product_images.product_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  );

-- 004_orders_payments.sql
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles (id) on delete restrict,
  status text not null default 'pending_payment'
    check (status in (
      'pending_payment',
      'paid',
      'processing',
      'shipped',
      'delivered',
      'cancelled',
      'refunded'
    )),
  currency text not null default 'PKR',
  subtotal_pkr integer not null check (subtotal_pkr >= 0),
  shipping_pkr integer not null default 0 check (shipping_pkr >= 0),
  total_pkr integer not null check (total_pkr >= 0),
  shipping_address jsonb,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists orders_buyer_id_idx on public.orders (buyer_id);
create index if not exists orders_status_idx on public.orders (status);

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  seller_id uuid references public.sellers (id) on delete set null,
  title text not null,
  unit_price_pkr integer not null check (unit_price_pkr >= 0),
  quantity integer not null check (quantity > 0),
  line_total_pkr integer not null check (line_total_pkr >= 0)
);

create index if not exists order_items_order_id_idx on public.order_items (order_id);
create index if not exists order_items_seller_id_idx on public.order_items (seller_id);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete restrict,
  purpose text not null check (purpose in ('order', 'seller_activation')),
  order_id uuid references public.orders (id) on delete set null,
  seller_id uuid references public.sellers (id) on delete set null,
  provider text not null default 'payfast',
  amount_pkr integer not null check (amount_pkr > 0),
  currency text not null default 'PKR',
  status text not null default 'initiated'
    check (status in ('initiated', 'pending', 'paid', 'failed', 'refunded')),
  provider_reference text,
  raw_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists payments_user_id_idx on public.payments (user_id);
create index if not exists payments_purpose_status_idx on public.payments (purpose, status);

drop trigger if exists payments_set_updated_at on public.payments;
create trigger payments_set_updated_at
before update on public.payments
for each row execute function public.set_updated_at();

alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;

drop policy if exists "orders_select_own" on public.orders;
create policy "orders_select_own"
  on public.orders for select
  using (auth.uid() = buyer_id);

drop policy if exists "orders_insert_own" on public.orders;
create policy "orders_insert_own"
  on public.orders for insert
  with check (auth.uid() = buyer_id);

drop policy if exists "orders_update_own" on public.orders;
create policy "orders_update_own"
  on public.orders for update
  using (auth.uid() = buyer_id);

drop policy if exists "order_items_select_buyer_or_seller" on public.order_items;
create policy "order_items_select_buyer_or_seller"
  on public.order_items for select
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.buyer_id = auth.uid()
    )
    or exists (
      select 1 from public.sellers s
      where s.id = order_items.seller_id and s.user_id = auth.uid()
    )
  );

drop policy if exists "order_items_insert_via_buyer_order" on public.order_items;
create policy "order_items_insert_via_buyer_order"
  on public.order_items for insert
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.buyer_id = auth.uid()
    )
  );

drop policy if exists "payments_select_own" on public.payments;
create policy "payments_select_own"
  on public.payments for select
  using (auth.uid() = user_id);

drop policy if exists "payments_insert_own" on public.payments;
create policy "payments_insert_own"
  on public.payments for insert
  with check (auth.uid() = user_id);

-- =============================================================================
-- Contact inquiries (public form submissions)
-- =============================================================================

create table if not exists public.contact_inquiries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  name text not null,
  email text not null,
  subject text not null,
  message text not null,
  status text not null default 'new'
    check (status in ('new', 'open', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists contact_inquiries_created_at_idx
  on public.contact_inquiries (created_at desc);

create index if not exists contact_inquiries_status_idx
  on public.contact_inquiries (status);

create index if not exists contact_inquiries_user_id_idx
  on public.contact_inquiries (user_id)
  where user_id is not null;

drop trigger if exists contact_inquiries_set_updated_at on public.contact_inquiries;
create trigger contact_inquiries_set_updated_at
before update on public.contact_inquiries
for each row execute function public.set_updated_at();

alter table public.contact_inquiries enable row level security;

grant insert on public.contact_inquiries to anon, authenticated;
grant select on public.contact_inquiries to authenticated;

drop policy if exists contact_inquiries_insert_public on public.contact_inquiries;
create policy contact_inquiries_insert_public
  on public.contact_inquiries
  for insert
  to anon, authenticated
  with check (
    user_id is null
    or user_id = auth.uid()
  );

drop policy if exists contact_inquiries_select_own on public.contact_inquiries;
create policy contact_inquiries_select_own
  on public.contact_inquiries
  for select
  to authenticated
  using (auth.uid() = user_id);

-- Done. Table Editor should show: profiles, addresses, sellers, categories,
-- products, product_images, orders, order_items, payments, contact_inquiries
