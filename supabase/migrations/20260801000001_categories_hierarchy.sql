-- Hierarchical marketplace categories (departments + nested leaves)
-- Used by /categories hub, /collection/[slug], megas, and filters.

alter table public.categories
  add column if not exists description text,
  add column if not exists parent_id uuid references public.categories (id) on delete cascade,
  add column if not exists is_department boolean not null default false;

create index if not exists categories_parent_id_idx on public.categories (parent_id);
create index if not exists categories_is_department_idx on public.categories (is_department);

-- Upsert helper: insert department then children by parent slug
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

-- Departments
select public.seed_category_tree('electronics', 'Electronics', 'Phones, laptops, audio and gadgets.', 'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?auto=format&fit=crop&w=900&q=80', 10, null, true);
select public.seed_category_tree('fashion', 'Fashion', 'Women, men, footwear and accessories.', 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=900&q=80', 20, null, true);
select public.seed_category_tree('home', 'Home', 'Kitchen, furniture, décor and appliances.', 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&w=900&q=80', 30, null, true);
select public.seed_category_tree('beauty', 'Beauty', 'Skincare, makeup and personal care.', 'https://images.unsplash.com/photo-1596462502278-27bfdc403348?auto=format&fit=crop&w=900&q=80', 40, null, true);
select public.seed_category_tree('sports', 'Sports', 'Fitness, outdoor and team gear.', 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?auto=format&fit=crop&w=900&q=80', 50, null, true);
select public.seed_category_tree('kids', 'Kids', 'Toys, baby care and school essentials.', 'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=900&q=80', 60, null, true);
select public.seed_category_tree('grocery', 'Grocery', 'Pantry, snacks and household.', 'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=900&q=80', 70, null, true);
select public.seed_category_tree('auto', 'Auto', 'Car care, tools and accessories.', 'https://images.unsplash.com/photo-1486262715619-67b85e0b08d3?auto=format&fit=crop&w=900&q=80', 80, null, true);
select public.seed_category_tree('books', 'Books', 'Books, study and stationery.', 'https://images.unsplash.com/photo-1512820790803-83ca734da794?auto=format&fit=crop&w=900&q=80', 90, null, true);
select public.seed_category_tree('pets', 'Pets', 'Food, toys and pet care.', 'https://images.unsplash.com/photo-1450778869180-41d0601e046e?auto=format&fit=crop&w=900&q=80', 100, null, true);
select public.seed_category_tree('office', 'Office', 'Desks, supplies and work gear.', 'https://images.unsplash.com/photo-1497366216548-37526070297c?auto=format&fit=crop&w=900&q=80', 110, null, true);

-- Electronics children
select public.seed_category_tree('electronics-mobiles', 'Mobiles', null, 'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?auto=format&fit=crop&w=600&q=80', 11, 'electronics', false);
select public.seed_category_tree('electronics-laptops', 'Laptops', null, 'https://images.unsplash.com/photo-1496181133206-80ce9b88a853?auto=format&fit=crop&w=600&q=80', 12, 'electronics', false);
select public.seed_category_tree('electronics-tablets', 'Tablets', null, 'https://images.unsplash.com/photo-1544244015-0df4b3ffc6b0?auto=format&fit=crop&w=600&q=80', 13, 'electronics', false);
select public.seed_category_tree('electronics-audio', 'Audio', null, 'https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?auto=format&fit=crop&w=600&q=80', 14, 'electronics', false);
select public.seed_category_tree('electronics-wearables', 'Wearables', null, 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=600&q=80', 15, 'electronics', false);
select public.seed_category_tree('electronics-cameras', 'Cameras', null, 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?auto=format&fit=crop&w=600&q=80', 16, 'electronics', false);
select public.seed_category_tree('electronics-tv', 'TV & displays', null, 'https://images.unsplash.com/photo-1593359677879-a4bb92f829d1?auto=format&fit=crop&w=600&q=80', 17, 'electronics', false);
select public.seed_category_tree('electronics-gaming', 'Gaming', null, 'https://images.unsplash.com/photo-1542751371-adc38448a05e?auto=format&fit=crop&w=600&q=80', 18, 'electronics', false);
select public.seed_category_tree('electronics-accessories', 'Accessories', null, 'https://images.unsplash.com/photo-1625948515291-69613efd103f?auto=format&fit=crop&w=600&q=80', 19, 'electronics', false);
select public.seed_category_tree('electronics-smart-home', 'Smart home', null, 'https://images.unsplash.com/photo-1558002038-1055907df827?auto=format&fit=crop&w=600&q=80', 20, 'electronics', false);

-- Fashion children
select public.seed_category_tree('fashion-women', 'Women', null, 'https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?auto=format&fit=crop&w=600&q=80', 21, 'fashion', false);
select public.seed_category_tree('fashion-men', 'Men', null, 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=600&q=80', 22, 'fashion', false);
select public.seed_category_tree('fashion-footwear', 'Footwear', null, 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=600&q=80', 23, 'fashion', false);
select public.seed_category_tree('fashion-bags', 'Bags', null, 'https://images.unsplash.com/photo-1548036328-c9fa89d128fa?auto=format&fit=crop&w=600&q=80', 24, 'fashion', false);
select public.seed_category_tree('fashion-traditional', 'Traditional', null, 'https://images.unsplash.com/photo-1585487000160-6ebcfceb0d03?auto=format&fit=crop&w=600&q=80', 25, 'fashion', false);
select public.seed_category_tree('fashion-jewelry', 'Jewelry', null, 'https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&w=600&q=80', 26, 'fashion', false);
select public.seed_category_tree('fashion-watches', 'Watches', null, 'https://images.unsplash.com/photo-1523170335258-f5ed11844a49?auto=format&fit=crop&w=600&q=80', 27, 'fashion', false);
select public.seed_category_tree('fashion-accessories', 'Accessories', null, 'https://images.unsplash.com/photo-1523170335258-f5ed11844a49?auto=format&fit=crop&w=600&q=80', 28, 'fashion', false);

-- Home children
select public.seed_category_tree('home-kitchen', 'Kitchen', null, 'https://images.unsplash.com/photo-1556910103-1c02745aae4d?auto=format&fit=crop&w=600&q=80', 31, 'home', false);
select public.seed_category_tree('home-furniture', 'Furniture', null, 'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?auto=format&fit=crop&w=600&q=80', 32, 'home', false);
select public.seed_category_tree('home-decor', 'Decor', null, 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&w=600&q=80', 33, 'home', false);
select public.seed_category_tree('home-bedding', 'Bedding', null, 'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&w=600&q=80', 34, 'home', false);
select public.seed_category_tree('home-bath', 'Bath', null, 'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=600&q=80', 35, 'home', false);
select public.seed_category_tree('home-storage', 'Storage', null, 'https://images.unsplash.com/photo-1595428774223-ef52624120d2?auto=format&fit=crop&w=600&q=80', 36, 'home', false);
select public.seed_category_tree('home-appliances', 'Appliances', null, 'https://images.unsplash.com/photo-1574269909862-7e1d70bb8078?auto=format&fit=crop&w=600&q=80', 37, 'home', false);
select public.seed_category_tree('home-lighting', 'Lighting', null, 'https://images.unsplash.com/photo-1507473885765-e6ed057f782c?auto=format&fit=crop&w=600&q=80', 38, 'home', false);

-- Beauty / Sports / Kids (sample nested)
select public.seed_category_tree('beauty-skincare', 'Skincare', null, 'https://images.unsplash.com/photo-1556228578-0d85b1a4d571?auto=format&fit=crop&w=600&q=80', 41, 'beauty', false);
select public.seed_category_tree('beauty-makeup', 'Makeup', null, 'https://images.unsplash.com/photo-1596462502278-27bfdc403348?auto=format&fit=crop&w=600&q=80', 42, 'beauty', false);
select public.seed_category_tree('beauty-hair', 'Haircare', null, 'https://images.unsplash.com/photo-1522337360788-8b13dee7a37e?auto=format&fit=crop&w=600&q=80', 43, 'beauty', false);
select public.seed_category_tree('beauty-fragrance', 'Fragrance', null, 'https://images.unsplash.com/photo-1541643600914-78b084683601?auto=format&fit=crop&w=600&q=80', 44, 'beauty', false);
select public.seed_category_tree('beauty-personal', 'Personal care', null, 'https://images.unsplash.com/photo-1571781926291-c477ebfd024b?auto=format&fit=crop&w=600&q=80', 45, 'beauty', false);

select public.seed_category_tree('sports-fitness', 'Fitness', null, 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?auto=format&fit=crop&w=600&q=80', 51, 'sports', false);
select public.seed_category_tree('sports-outdoor', 'Outdoor', null, 'https://images.unsplash.com/photo-1551632811-561732d1e306?auto=format&fit=crop&w=600&q=80', 52, 'sports', false);
select public.seed_category_tree('sports-cycling', 'Cycling', null, 'https://images.unsplash.com/photo-1485965120184-cf9d2cd9b2d0?auto=format&fit=crop&w=600&q=80', 53, 'sports', false);
select public.seed_category_tree('sports-team', 'Team sports', null, 'https://images.unsplash.com/photo-1574629810360-7efbbe195018?auto=format&fit=crop&w=600&q=80', 54, 'sports', false);
select public.seed_category_tree('sports-apparel', 'Apparel', null, 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?auto=format&fit=crop&w=600&q=80', 55, 'sports', false);

select public.seed_category_tree('kids-toys', 'Toys', null, 'https://images.unsplash.com/photo-1587654780291-39c9404d746b?auto=format&fit=crop&w=600&q=80', 61, 'kids', false);
select public.seed_category_tree('kids-baby', 'Baby care', null, 'https://images.unsplash.com/photo-1515488764276-beab7607c1e6?auto=format&fit=crop&w=600&q=80', 62, 'kids', false);
select public.seed_category_tree('kids-school', 'School', null, 'https://images.unsplash.com/photo-1503676260728-1c00da094a0b?auto=format&fit=crop&w=600&q=80', 63, 'kids', false);
select public.seed_category_tree('kids-clothing', 'Clothing', null, 'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=600&q=80', 64, 'kids', false);
select public.seed_category_tree('kids-gear', 'Gear', null, 'https://images.unsplash.com/photo-1596464114860-aee2b4e1a4f4?auto=format&fit=crop&w=600&q=80', 65, 'kids', false);

select public.seed_category_tree('grocery-snacks', 'Snacks', null, null, 71, 'grocery', false);
select public.seed_category_tree('grocery-drinks', 'Beverages', null, null, 72, 'grocery', false);
select public.seed_category_tree('grocery-staples', 'Staples', null, null, 73, 'grocery', false);
select public.seed_category_tree('grocery-household', 'Household', null, null, 74, 'grocery', false);

select public.seed_category_tree('auto-care', 'Car care', null, null, 81, 'auto', false);
select public.seed_category_tree('auto-accessories', 'Accessories', null, null, 82, 'auto', false);
select public.seed_category_tree('auto-tools', 'Tools', null, null, 83, 'auto', false);

select public.seed_category_tree('books-fiction', 'Fiction', null, null, 91, 'books', false);
select public.seed_category_tree('books-nonfiction', 'Non-fiction', null, null, 92, 'books', false);
select public.seed_category_tree('books-study', 'Study', null, null, 93, 'books', false);
select public.seed_category_tree('books-stationery', 'Stationery', null, null, 94, 'books', false);

select public.seed_category_tree('pets-dog', 'Dog', null, null, 101, 'pets', false);
select public.seed_category_tree('pets-cat', 'Cat', null, null, 102, 'pets', false);
select public.seed_category_tree('pets-food', 'Food', null, null, 103, 'pets', false);

select public.seed_category_tree('office-desks', 'Desks', null, null, 111, 'office', false);
select public.seed_category_tree('office-chairs', 'Chairs', null, null, 112, 'office', false);
select public.seed_category_tree('office-supplies', 'Supplies', null, null, 113, 'office', false);

drop function if exists public.seed_category_tree(text, text, text, text, integer, text, boolean);
