-- Merchandising layer on top of product options/variants.
--
-- Adds the three things the catalog and storefront need but the variant tables
-- alone do not provide:
--   1. Tags + a single searchable text column, so browse/search can filter on
--      tags, brand, category, colors and sizes without N separate ilike clauses.
--   2. Stock that stays truthful — a product with variants derives its stock
--      from the sum of its variants, and checkout draws stock down.
--   3. The variant a buyer actually chose, recorded on the order line.

create extension if not exists pg_trgm;

-- ——— tags + low-stock threshold ———

alter table public.products
  add column if not exists tags text[] not null default '{}',
  add column if not exists low_stock_threshold integer not null default 5
    check (low_stock_threshold >= 0);

create index if not exists products_tags_idx on public.products using gin (tags);

-- ——— one searchable column ———
-- A plain column kept current by trigger rather than `generated always as`,
-- because array_to_string is only STABLE and Postgres rejects it in a generation
-- expression. PostgREST filters it directly with `ilike`, backed by a trigram
-- index — the previous search was a title-only ilike with no index at all.

alter table public.products
  add column if not exists search_text text;

create or replace function public.products_build_search_text()
returns trigger
language plpgsql
as $$
begin
  new.search_text := lower(
    coalesce(new.title, '') || ' ' ||
    coalesce(new.brand, '') || ' ' ||
    coalesce(new.category_slug, '') || ' ' ||
    coalesce(array_to_string(new.tags, ' '), '') || ' ' ||
    coalesce(array_to_string(new.colors, ' '), '') || ' ' ||
    coalesce(array_to_string(new.sizes, ' '), '') || ' ' ||
    coalesce(new.description, '')
  );
  return new;
end;
$$;

drop trigger if exists products_set_search_text on public.products;
create trigger products_set_search_text
before insert or update of title, brand, category_slug, tags, colors, sizes, description
on public.products
for each row execute function public.products_build_search_text();

update public.products
   set search_text = lower(
     coalesce(title, '') || ' ' ||
     coalesce(brand, '') || ' ' ||
     coalesce(category_slug, '') || ' ' ||
     coalesce(array_to_string(tags, ' '), '') || ' ' ||
     coalesce(array_to_string(colors, ' '), '') || ' ' ||
     coalesce(array_to_string(sizes, ' '), '') || ' ' ||
     coalesce(description, '')
   );

create index if not exists products_search_text_trgm_idx
  on public.products using gin (search_text gin_trgm_ops);

-- Array-overlap filters (`colors && {...}`) need GIN to stay cheap.
create index if not exists products_colors_idx on public.products using gin (colors);
create index if not exists products_sizes_idx on public.products using gin (sizes);
create index if not exists products_price_pkr_idx on public.products (price_pkr);

-- ——— variant stock rolls up to the product ———

create or replace function public.sync_product_stock_from_variants()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid := coalesce(new.product_id, old.product_id);
  variant_count integer;
  variant_stock integer;
begin
  select count(*), coalesce(sum(stock), 0)
    into variant_count, variant_stock
    from public.product_variants
   where product_id = target;

  -- A product with no variants keeps whatever stock the seller typed in.
  if variant_count > 0 then
    update public.products
       set stock = variant_stock
     where id = target
       and stock is distinct from variant_stock;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists product_variants_sync_stock on public.product_variants;
create trigger product_variants_sync_stock
after insert or update of stock or delete on public.product_variants
for each row execute function public.sync_product_stock_from_variants();

-- ——— the chosen variant, recorded on the order line ———

alter table public.order_items
  add column if not exists variant_id uuid
    references public.product_variants (id) on delete set null,
  add column if not exists variant_label text;

create index if not exists order_items_variant_id_idx on public.order_items (variant_id);

-- ——— checkout draws stock down, cancellation puts it back ———

create or replace function public.apply_order_item_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.variant_id is not null then
    update public.product_variants
       set stock = greatest(stock - new.quantity, 0)
     where id = new.variant_id;
  elsif new.product_id is not null then
    update public.products
       set stock = greatest(stock - new.quantity, 0)
     where id = new.product_id;
  end if;

  return new;
end;
$$;

drop trigger if exists order_items_apply_stock on public.order_items;
create trigger order_items_apply_stock
after insert on public.order_items
for each row execute function public.apply_order_item_stock();

create or replace function public.restore_order_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.product_variants v
     set stock = v.stock + oi.quantity
    from public.order_items oi
   where oi.order_id = new.id
     and oi.variant_id = v.id;

  update public.products p
     set stock = p.stock + oi.quantity
    from public.order_items oi
   where oi.order_id = new.id
     and oi.variant_id is null
     and oi.product_id = p.id;

  return new;
end;
$$;

-- Fires only on the transition into a cancelled state, so stock is never
-- credited twice by repeated updates to an already-cancelled order.
drop trigger if exists orders_restore_stock on public.orders;
create trigger orders_restore_stock
after update on public.orders
for each row
when (
  new.status in ('cancelled', 'refunded')
  and old.status is distinct from new.status
  and old.status not in ('cancelled', 'refunded')
)
execute function public.restore_order_stock();
