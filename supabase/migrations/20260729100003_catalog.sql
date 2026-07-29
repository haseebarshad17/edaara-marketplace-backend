-- 003_catalog.sql
-- Seller-owned products (admin catalog tools come later)

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

create policy "categories_select_all"
  on public.categories for select
  using (true);

create policy "products_select_active_or_owner"
  on public.products for select
  using (
    status = 'active'
    or exists (
      select 1 from public.sellers s
      where s.id = products.seller_id and s.user_id = auth.uid()
    )
  );

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
