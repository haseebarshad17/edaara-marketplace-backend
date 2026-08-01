-- Women & Men as top-level departments with nested shops
-- (supports /categories/women, /categories/men + scoped search)

create or replace function public.seed_category_tree(
  p_slug text,
  p_name text,
  p_description text,
  p_image_url text,
  p_sort integer,
  p_parent_slug text default null,
  p_is_department boolean default false
)
returns void
language plpgsql
as $$
declare
  v_parent uuid;
begin
  if p_parent_slug is not null then
    select id into v_parent from public.categories where slug = p_parent_slug;
  end if;

  insert into public.categories (slug, name, description, image_url, sort_order, parent_id, is_department)
  values (p_slug, p_name, p_description, p_image_url, p_sort, v_parent, p_is_department)
  on conflict (slug) do update set
    name = excluded.name,
    description = excluded.description,
    image_url = coalesce(excluded.image_url, public.categories.image_url),
    sort_order = excluded.sort_order,
    parent_id = excluded.parent_id,
    is_department = excluded.is_department;
end;
$$;

select public.seed_category_tree(
  'women'::text,
  'Women'::text,
  'Clothing, bags, shoes and accessories for women.'::text,
  'https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?auto=format&fit=crop&w=900&q=80'::text,
  15,
  null::text,
  true
);

select public.seed_category_tree(
  'men'::text,
  'Men'::text,
  'Clothing, footwear and accessories for men.'::text,
  'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=900&q=80'::text,
  16,
  null::text,
  true
);

-- Women children
select public.seed_category_tree('women-tops'::text, 'Tops'::text, null::text, 'https://images.unsplash.com/photo-1434389677669-e08b4cac3105?auto=format&fit=crop&w=600&q=80'::text, 151, 'women'::text, false);
select public.seed_category_tree('women-blouses'::text, 'Blouses'::text, null::text, 'https://images.unsplash.com/photo-1564257631407-4deb1f99d992?auto=format&fit=crop&w=600&q=80'::text, 152, 'women'::text, false);
select public.seed_category_tree('women-dresses'::text, 'Dresses'::text, null::text, 'https://images.unsplash.com/photo-1595777457583-95e059d581b8?auto=format&fit=crop&w=600&q=80'::text, 153, 'women'::text, false);
select public.seed_category_tree('women-bottoms'::text, 'Bottoms'::text, null::text, 'https://images.unsplash.com/photo-1541099649105-f69ad21f3246?auto=format&fit=crop&w=600&q=80'::text, 154, 'women'::text, false);
select public.seed_category_tree('women-bags'::text, 'Bags'::text, null::text, 'https://images.unsplash.com/photo-1548036328-c9fa89d128fa?auto=format&fit=crop&w=600&q=80'::text, 155, 'women'::text, false);
select public.seed_category_tree('women-shoes'::text, 'Shoes'::text, null::text, 'https://images.unsplash.com/photo-1543163521-1bf539c55dd2?auto=format&fit=crop&w=600&q=80'::text, 156, 'women'::text, false);
select public.seed_category_tree('women-jewelry'::text, 'Jewelry'::text, null::text, 'https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&w=600&q=80'::text, 157, 'women'::text, false);
select public.seed_category_tree('women-accessories'::text, 'Accessories'::text, null::text, 'https://images.unsplash.com/photo-1523170335258-f5ed11844a49?auto=format&fit=crop&w=600&q=80'::text, 158, 'women'::text, false);
select public.seed_category_tree('women-traditional'::text, 'Traditional'::text, null::text, 'https://images.unsplash.com/photo-1585487000160-6ebcfceb0d03?auto=format&fit=crop&w=600&q=80'::text, 159, 'women'::text, false);
select public.seed_category_tree('women-outerwear'::text, 'Outerwear'::text, null::text, 'https://images.unsplash.com/photo-1539533018447-63fcce2678e3?auto=format&fit=crop&w=600&q=80'::text, 160, 'women'::text, false);

-- Men children
select public.seed_category_tree('men-shirts'::text, 'Shirts'::text, null::text, 'https://images.unsplash.com/photo-1596755094514-f87e34085b2c?auto=format&fit=crop&w=600&q=80'::text, 161, 'men'::text, false);
select public.seed_category_tree('men-tshirts'::text, 'T-Shirts'::text, null::text, 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=600&q=80'::text, 162, 'men'::text, false);
select public.seed_category_tree('men-pants'::text, 'Pants'::text, null::text, 'https://images.unsplash.com/photo-1473966968600-fa801b869a1a?auto=format&fit=crop&w=600&q=80'::text, 163, 'men'::text, false);
select public.seed_category_tree('men-shoes'::text, 'Shoes'::text, null::text, 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=600&q=80'::text, 164, 'men'::text, false);
select public.seed_category_tree('men-bags'::text, 'Bags'::text, null::text, 'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?auto=format&fit=crop&w=600&q=80'::text, 165, 'men'::text, false);
select public.seed_category_tree('men-watches'::text, 'Watches'::text, null::text, 'https://images.unsplash.com/photo-1523170335258-f5ed11844a49?auto=format&fit=crop&w=600&q=80'::text, 166, 'men'::text, false);
select public.seed_category_tree('men-accessories'::text, 'Accessories'::text, null::text, 'https://images.unsplash.com/photo-1624222247344-550fb60583fd?auto=format&fit=crop&w=600&q=80'::text, 167, 'men'::text, false);
select public.seed_category_tree('men-traditional'::text, 'Traditional'::text, null::text, 'https://images.unsplash.com/photo-1585487000160-6ebcfceb0d03?auto=format&fit=crop&w=600&q=80'::text, 168, 'men'::text, false);
select public.seed_category_tree('men-outerwear'::text, 'Outerwear'::text, null::text, 'https://images.unsplash.com/photo-1551028719-00167b16eac5?auto=format&fit=crop&w=600&q=80'::text, 169, 'men'::text, false);
select public.seed_category_tree('men-activewear'::text, 'Activewear'::text, null::text, 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?auto=format&fit=crop&w=600&q=80'::text, 170, 'men'::text, false);
