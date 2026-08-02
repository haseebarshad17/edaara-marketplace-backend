-- Review authors visible to guests + richer catalog seed

alter table public.product_reviews
  add column if not exists author_name text,
  add column if not exists author_avatar text;

-- Backfill from profiles (migration runs with elevated privileges)
update public.product_reviews r
set
  author_name = coalesce(nullif(trim(p.full_name), ''), split_part(coalesce(p.email, 'shopper'), '@', 1)),
  author_avatar = p.avatar_url
from public.profiles p
where p.id = r.user_id
  and (r.author_name is null or r.author_avatar is null);

-- Public read of display fields only via denormalized review columns (no profiles leak)

-- Extra catalog seed for home rails / filters / related
insert into public.products (
  seller_id, title, slug, description, price_pkr, compare_at_pkr, stock, status,
  category_slug, cover_image_url, brand, colors, sizes, badge
) values
(
  null, 'Silk scarf — desert rose', 'silk-scarf-desert-rose',
  'Lightweight silk scarf with a soft drape. Finishes any outfit.',
  2499, null, 70, 'active', 'women',
  'https://images.unsplash.com/photo-1601924999987-b6eaf2a3c4c5?auto=format&fit=crop&w=1200&q=80',
  'Loom & Co', array['pink', 'beige'], array['One size'], 'new'
),
(
  null, 'Tailored chino pants', 'tailored-chino-pants',
  'Slim-straight chinos in stretch cotton. Office to weekend.',
  5499, 6499, 48, 'active', 'men',
  'https://images.unsplash.com/photo-1473966968600-fa801b869a1a?auto=format&fit=crop&w=1200&q=80',
  'DailyWear', array['khaki', 'navy', 'black'], array['30', '32', '34', '36'], 'sale'
),
(
  null, 'Kids denim jacket', 'kids-denim-jacket',
  'Classic trucker jacket with soft lining for cool evenings.',
  3999, null, 36, 'active', 'kids',
  'https://images.unsplash.com/photo-1519238263530-99bdd11df2ea?auto=format&fit=crop&w=1200&q=80',
  'LittleTrail', array['blue'], array['4Y', '6Y', '8Y', '10Y'], 'bestseller'
),
(
  null, 'Bluetooth speaker mini', 'bluetooth-speaker-mini',
  'Pocket speaker with punchy bass and 12-hour playtime.',
  4599, 5299, 90, 'active', 'electronics',
  'https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?auto=format&fit=crop&w=1200&q=80',
  'SoundMax', array['black', 'blue'], array['One size'], 'sale'
),
(
  null, 'Matte desk lamp', 'matte-desk-lamp',
  'Adjustable arm lamp with warm LED. Cable-free look on any desk.',
  6799, null, 28, 'active', 'home',
  'https://images.unsplash.com/photo-1507473885765-e6ed057f782c?auto=format&fit=crop&w=1200&q=80',
  'Hearth', array['black', 'white'], array['One size'], 'new'
),
(
  null, 'Yoga mat — cloud foam', 'yoga-mat-cloud-foam',
  'Non-slip mat with extra cushion. Rolls tight for the gym bag.',
  3299, null, 60, 'active', 'sports',
  'https://images.unsplash.com/photo-1601925260368-ae2f83cf8b7f?auto=format&fit=crop&w=1200&q=80',
  'Stride', array['purple', 'teal'], array['One size'], 'bestseller'
),
(
  null, 'Gold hoop earrings', 'gold-hoop-earrings',
  'Lightweight hoops with a brushed finish. Everyday elegance.',
  1999, 2499, 100, 'active', 'fashion',
  'https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&w=1200&q=80',
  'Atelier', array['gold'], array['One size'], 'sale'
),
(
  null, 'Vitamin C bright serum', 'vitamin-c-bright-serum',
  'Morning serum for glow. Pair with SPF for best results.',
  3499, null, 75, 'active', 'beauty',
  'https://images.unsplash.com/photo-1620916565856-d5d598e3bf1b?auto=format&fit=crop&w=1200&q=80',
  'GlowLab', array['orange'], array['30ml'], 'new'
),
(
  null, 'Cotton crew socks (3-pack)', 'cotton-crew-socks-3-pack',
  'Breathable crew socks with reinforced heel and toe.',
  999, null, 200, 'active', 'men',
  'https://images.unsplash.com/photo-1586350977771-b3b0abd50c40?auto=format&fit=crop&w=1200&q=80',
  'DailyWear', array['white', 'grey', 'black'], array['M', 'L'], null
),
(
  null, 'Canvas tote — market day', 'canvas-tote-market-day',
  'Roomy canvas tote with inner pocket. Errands, books, beach.',
  1799, null, 85, 'active', 'women',
  'https://images.unsplash.com/photo-1590874103328-eac38a683ce7?auto=format&fit=crop&w=1200&q=80',
  'Loom & Co', array['beige', 'navy'], array['One size'], 'bestseller'
),
(
  null, 'USB-C hub 7-in-1', 'usb-c-hub-7-in-1',
  'HDMI, USB-A, SD, and power passthrough for slim laptops.',
  5999, 6999, 40, 'active', 'electronics',
  'https://images.unsplash.com/photo-1625948515291-69613efd2566?auto=format&fit=crop&w=1200&q=80',
  'SoundMax', array['silver'], array['One size'], 'sale'
),
(
  null, 'Stoneware dinner plate set', 'stoneware-dinner-plate-set',
  'Set of 4 matte plates. Microwave and dishwasher safe.',
  4899, null, 32, 'active', 'home',
  'https://images.unsplash.com/photo-1578500494198-246f612d3b3d?auto=format&fit=crop&w=1200&q=80',
  'Hearth', array['sage', 'sand'], array['One size'], 'new'
)
on conflict (slug) do update set
  title = excluded.title,
  description = excluded.description,
  price_pkr = excluded.price_pkr,
  compare_at_pkr = excluded.compare_at_pkr,
  stock = excluded.stock,
  status = 'active',
  category_slug = excluded.category_slug,
  cover_image_url = excluded.cover_image_url,
  brand = excluded.brand,
  colors = excluded.colors,
  sizes = excluded.sizes,
  badge = excluded.badge,
  updated_at = now();

-- Ensure each seeded product has at least a cover gallery row
insert into public.product_images (product_id, url, sort_order)
select p.id, p.cover_image_url, 0
from public.products p
where p.cover_image_url is not null
  and not exists (
    select 1 from public.product_images pi
    where pi.product_id = p.id and pi.sort_order = 0
  );
