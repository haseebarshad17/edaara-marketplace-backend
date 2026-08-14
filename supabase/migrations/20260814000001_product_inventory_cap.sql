-- Declared stock in hand is independent of variant allocation.
-- products.stock remains available-to-sell (sum of variants when variants exist).
-- inventory_cap is the pool the seller declared; SKU quantities cannot exceed it.

alter table public.products
  add column if not exists inventory_cap integer not null default 0
    check (inventory_cap >= 0);

update public.products
   set inventory_cap = stock
 where inventory_cap is distinct from stock;

create or replace function public.enforce_inventory_cap()
returns trigger
language plpgsql
as $$
declare
  target uuid := coalesce(new.product_id, old.product_id);
  cap integer;
  allocated integer;
begin
  select inventory_cap into cap
    from public.products
   where id = target;

  select coalesce(sum(stock), 0) into allocated
    from public.product_variants
   where product_id = target;

  if allocated > coalesce(cap, 0) then
    raise exception 'Variant stock (%) exceeds inventory cap (%)', allocated, cap
      using errcode = '23514';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists product_variants_enforce_inventory_cap on public.product_variants;
create trigger product_variants_enforce_inventory_cap
after insert or update of stock or delete on public.product_variants
for each row execute function public.enforce_inventory_cap();

create or replace function public.enforce_inventory_cap_on_product()
returns trigger
language plpgsql
as $$
declare
  allocated integer;
  variant_count integer;
begin
  select count(*), coalesce(sum(stock), 0)
    into variant_count, allocated
    from public.product_variants
   where product_id = new.id;

  if variant_count > 0 and allocated > new.inventory_cap then
    raise exception 'Inventory cap (%) is below allocated variant stock (%)', new.inventory_cap, allocated
      using errcode = '23514';
  end if;

  if variant_count = 0 then
    if new.inventory_cap = 0 and new.stock > 0 then
      new.inventory_cap := new.stock;
    else
      new.stock := new.inventory_cap;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists products_enforce_inventory_cap on public.products;
create trigger products_enforce_inventory_cap
before insert or update of inventory_cap, stock on public.products
for each row execute function public.enforce_inventory_cap_on_product();
