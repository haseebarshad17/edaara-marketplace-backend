-- 004_orders_payments.sql
-- Checkout orders + PayFast payments (buyer orders & seller activation)

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

create policy "orders_select_own"
  on public.orders for select
  using (auth.uid() = buyer_id);

create policy "orders_insert_own"
  on public.orders for insert
  with check (auth.uid() = buyer_id);

create policy "orders_update_own"
  on public.orders for update
  using (auth.uid() = buyer_id);

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

create policy "order_items_insert_via_buyer_order"
  on public.order_items for insert
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.buyer_id = auth.uid()
    )
  );

create policy "payments_select_own"
  on public.payments for select
  using (auth.uid() = user_id);

create policy "payments_insert_own"
  on public.payments for insert
  with check (auth.uid() = user_id);
