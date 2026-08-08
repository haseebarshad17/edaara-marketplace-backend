-- Flexible product options + variants.
-- A product can define any number of option groups (Color, Size, Storage, Material, ...),
-- each with any number of values. A variant is a specific combination of one value per
-- group (e.g. Color=Black + Size=M), with its own SKU/price/stock/image. Nothing about
-- "color" or "size" is hardcoded — sellers define whatever option groups their product needs.

create table if not exists public.product_option_groups (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists product_option_groups_product_id_idx
  on public.product_option_groups (product_id);

create table if not exists public.product_option_values (
  id uuid primary key default gen_random_uuid(),
  option_group_id uuid not null references public.product_option_groups (id) on delete cascade,
  value text not null,
  swatch_hex text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists product_option_values_group_id_idx
  on public.product_option_values (option_group_id);

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  sku text,
  price_pkr integer check (price_pkr is null or price_pkr >= 0),
  stock integer not null default 0 check (stock >= 0),
  image_url text,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists product_variants_product_id_idx on public.product_variants (product_id);

drop trigger if exists product_variants_set_updated_at on public.product_variants;
create trigger product_variants_set_updated_at
before update on public.product_variants
for each row execute function public.set_updated_at();

create table if not exists public.product_variant_option_values (
  variant_id uuid not null references public.product_variants (id) on delete cascade,
  option_value_id uuid not null references public.product_option_values (id) on delete cascade,
  primary key (variant_id, option_value_id)
);

create index if not exists product_variant_option_values_option_value_id_idx
  on public.product_variant_option_values (option_value_id);

alter table public.product_option_groups enable row level security;
alter table public.product_option_values enable row level security;
alter table public.product_variants enable row level security;
alter table public.product_variant_option_values enable row level security;

-- ——— product_option_groups ———

create policy "product_option_groups_select_via_product"
  on public.product_option_groups for select
  using (
    exists (
      select 1 from public.products p
      where p.id = product_option_groups.product_id
        and (
          p.status = 'active'
          or exists (
            select 1 from public.sellers s
            where s.id = p.seller_id and s.user_id = auth.uid()
          )
        )
    )
  );

create policy "product_option_groups_write_own"
  on public.product_option_groups for all
  using (
    exists (
      select 1 from public.products p
      join public.sellers s on s.id = p.seller_id
      where p.id = product_option_groups.product_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  )
  with check (
    exists (
      select 1 from public.products p
      join public.sellers s on s.id = p.seller_id
      where p.id = product_option_groups.product_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  );

-- ——— product_option_values ———

create policy "product_option_values_select_via_group"
  on public.product_option_values for select
  using (
    exists (
      select 1 from public.product_option_groups g
      join public.products p on p.id = g.product_id
      where g.id = product_option_values.option_group_id
        and (
          p.status = 'active'
          or exists (
            select 1 from public.sellers s
            where s.id = p.seller_id and s.user_id = auth.uid()
          )
        )
    )
  );

create policy "product_option_values_write_own"
  on public.product_option_values for all
  using (
    exists (
      select 1 from public.product_option_groups g
      join public.products p on p.id = g.product_id
      join public.sellers s on s.id = p.seller_id
      where g.id = product_option_values.option_group_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  )
  with check (
    exists (
      select 1 from public.product_option_groups g
      join public.products p on p.id = g.product_id
      join public.sellers s on s.id = p.seller_id
      where g.id = product_option_values.option_group_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  );

-- ——— product_variants ———

create policy "product_variants_select_via_product"
  on public.product_variants for select
  using (
    exists (
      select 1 from public.products p
      where p.id = product_variants.product_id
        and (
          p.status = 'active'
          or exists (
            select 1 from public.sellers s
            where s.id = p.seller_id and s.user_id = auth.uid()
          )
        )
    )
  );

create policy "product_variants_write_own"
  on public.product_variants for all
  using (
    exists (
      select 1 from public.products p
      join public.sellers s on s.id = p.seller_id
      where p.id = product_variants.product_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  )
  with check (
    exists (
      select 1 from public.products p
      join public.sellers s on s.id = p.seller_id
      where p.id = product_variants.product_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  );

-- ——— product_variant_option_values ———

create policy "product_variant_option_values_select_via_variant"
  on public.product_variant_option_values for select
  using (
    exists (
      select 1 from public.product_variants v
      join public.products p on p.id = v.product_id
      where v.id = product_variant_option_values.variant_id
        and (
          p.status = 'active'
          or exists (
            select 1 from public.sellers s
            where s.id = p.seller_id and s.user_id = auth.uid()
          )
        )
    )
  );

create policy "product_variant_option_values_write_own"
  on public.product_variant_option_values for all
  using (
    exists (
      select 1 from public.product_variants v
      join public.products p on p.id = v.product_id
      join public.sellers s on s.id = p.seller_id
      where v.id = product_variant_option_values.variant_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  )
  with check (
    exists (
      select 1 from public.product_variants v
      join public.products p on p.id = v.product_id
      join public.sellers s on s.id = p.seller_id
      where v.id = product_variant_option_values.variant_id
        and s.user_id = auth.uid()
        and s.status = 'active'
    )
  );
