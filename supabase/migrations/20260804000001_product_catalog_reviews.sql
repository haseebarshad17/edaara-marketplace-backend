-- Product catalog attrs, global slug, platform products, reviews + images

-- Allow marketplace / future-admin catalog without a seller
alter table public.products
  alter column seller_id drop not null;

alter table public.products
  add column if not exists brand text,
  add column if not exists colors text[] not null default '{}',
  add column if not exists sizes text[] not null default '{}',
  add column if not exists badge text
    check (badge is null or badge in ('new', 'bestseller', 'sale')),
  add column if not exists rating_avg numeric(3, 2) not null default 0
    check (rating_avg >= 0 and rating_avg <= 5),
  add column if not exists review_count integer not null default 0
    check (review_count >= 0);

-- Stable public PDP URLs
create unique index if not exists products_slug_unique on public.products (slug);

create index if not exists products_brand_idx on public.products (brand);
create index if not exists products_colors_gin_idx on public.products using gin (colors);
create index if not exists products_badge_idx on public.products (badge);

-- ——— Reviews ———
create table if not exists public.product_reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  title text,
  body text not null check (char_length(trim(body)) >= 8),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, user_id)
);

-- Embed-friendly FK for PostgREST (profiles.id == auth.users.id)
alter table public.product_reviews
  drop constraint if exists product_reviews_user_id_fkey;

alter table public.product_reviews
  add constraint product_reviews_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;

create index if not exists product_reviews_product_id_idx
  on public.product_reviews (product_id, created_at desc);

drop trigger if exists product_reviews_set_updated_at on public.product_reviews;
create trigger product_reviews_set_updated_at
before update on public.product_reviews
for each row execute function public.set_updated_at();

create table if not exists public.product_review_images (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.product_reviews (id) on delete cascade,
  url text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists product_review_images_review_id_idx
  on public.product_review_images (review_id);

create or replace function public.refresh_product_rating(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.products p
  set
    rating_avg = coalesce((
      select round(avg(r.rating)::numeric, 2)
      from public.product_reviews r
      where r.product_id = p_product_id
    ), 0),
    review_count = coalesce((
      select count(*)::integer
      from public.product_reviews r
      where r.product_id = p_product_id
    ), 0)
  where p.id = p_product_id;
end;
$$;

create or replace function public.product_reviews_refresh_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_product_rating(old.product_id);
    return old;
  end if;
  perform public.refresh_product_rating(new.product_id);
  return new;
end;
$$;

drop trigger if exists product_reviews_refresh_rating on public.product_reviews;
create trigger product_reviews_refresh_rating
after insert or update or delete on public.product_reviews
for each row execute function public.product_reviews_refresh_rating();

alter table public.product_reviews enable row level security;
alter table public.product_review_images enable row level security;

create policy "product_reviews_select_public"
  on public.product_reviews for select
  using (
    exists (
      select 1 from public.products p
      where p.id = product_reviews.product_id and p.status = 'active'
    )
  );

create policy "product_reviews_insert_own"
  on public.product_reviews for insert
  with check (auth.uid() = user_id);

create policy "product_reviews_update_own"
  on public.product_reviews for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "product_reviews_delete_own"
  on public.product_reviews for delete
  using (auth.uid() = user_id);

create policy "product_review_images_select_public"
  on public.product_review_images for select
  using (
    exists (
      select 1
      from public.product_reviews r
      join public.products p on p.id = r.product_id
      where r.id = product_review_images.review_id and p.status = 'active'
    )
  );

create policy "product_review_images_write_own"
  on public.product_review_images for all
  using (
    exists (
      select 1 from public.product_reviews r
      where r.id = product_review_images.review_id and r.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.product_reviews r
      where r.id = product_review_images.review_id and r.user_id = auth.uid()
    )
  );

-- Review image storage
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'review-images',
  'review-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "review_images_public_read" on storage.objects;
create policy "review_images_public_read"
  on storage.objects for select
  using (bucket_id = 'review-images');

drop policy if exists "review_images_auth_upload" on storage.objects;
create policy "review_images_auth_upload"
  on storage.objects for insert
  with check (
    bucket_id = 'review-images'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "review_images_auth_update" on storage.objects;
create policy "review_images_auth_update"
  on storage.objects for update
  using (
    bucket_id = 'review-images'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "review_images_auth_delete" on storage.objects;
create policy "review_images_auth_delete"
  on storage.objects for delete
  using (
    bucket_id = 'review-images'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Demo platform catalog (seller_id null) — enough for shop + filters + PDP
insert into public.products (
  seller_id, title, slug, description, price_pkr, compare_at_pkr, stock, status,
  category_slug, cover_image_url, brand, colors, sizes, badge
) values
(
  null,
  'Wireless noise-canceling headphones',
  'wireless-noise-canceling-headphones',
  'Comfortable over-ear headphones with deep bass and all-day battery. Ideal for commute and work.',
  12999, 15999, 42, 'active',
  'electronics',
  'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=1200&q=80',
  'SoundMax', array['black', 'silver'], array['One size'], 'sale'
),
(
  null,
  'Classic linen shirt',
  'classic-linen-shirt',
  'Breathable linen shirt for warm days. Easy fit with a clean collar.',
  4499, null, 80, 'active',
  'women',
  'https://images.unsplash.com/photo-1596755094514-f87e34085b2c?auto=format&fit=crop&w=1200&q=80',
  'Loom & Co', array['white', 'beige', 'blue'], array['S', 'M', 'L', 'XL'], 'new'
),
(
  null,
  'Everyday cotton tee',
  'everyday-cotton-tee',
  'Soft mid-weight cotton tee. Pre-washed for a lived-in feel.',
  1899, 2499, 120, 'active',
  'men',
  'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=1200&q=80',
  'DailyWear', array['black', 'white', 'navy'], array['S', 'M', 'L', 'XL'], 'bestseller'
),
(
  null,
  'Kids graphic hoodie',
  'kids-graphic-hoodie',
  'Cozy fleece hoodie with a playful print. Soft inside, durable outside.',
  3299, null, 55, 'active',
  'kids',
  'https://images.unsplash.com/photo-1519238263530-99bdd11df2ea?auto=format&fit=crop&w=1200&q=80',
  'LittleTrail', array['red', 'blue', 'green'], array['4Y', '6Y', '8Y', '10Y'], 'new'
),
(
  null,
  'Ceramic pour-over set',
  'ceramic-pour-over-set',
  'Matte ceramic dripper with matching mug. Slow mornings, done right.',
  5699, 6499, 30, 'active',
  'home',
  'https://images.unsplash.com/photo-1514228742587-6b1558fcca3d?auto=format&fit=crop&w=1200&q=80',
  'Hearth', array['white', 'sage'], array['One size'], 'sale'
),
(
  null,
  'Running trainers',
  'running-trainers',
  'Lightweight trainers with cushioned midsole for city runs and gym days.',
  8999, null, 64, 'active',
  'sports',
  'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=1200&q=80',
  'Stride', array['black', 'white', 'red'], array['40', '41', '42', '43', '44'], 'bestseller'
),
(
  null,
  'Minimal leather tote',
  'minimal-leather-tote',
  'Structured tote in soft leather. Fits a 14\" laptop and daily essentials.',
  11999, 13999, 22, 'active',
  'fashion',
  'https://images.unsplash.com/photo-1590874103328-eac38a683ce7?auto=format&fit=crop&w=1200&q=80',
  'Atelier', array['tan', 'black'], array['One size'], 'sale'
),
(
  null,
  'Hydrating face serum',
  'hydrating-face-serum',
  'Lightweight serum with hyaluronic acid. Fragrance-free and dermatologist tested.',
  2799, null, 90, 'active',
  'beauty',
  'https://images.unsplash.com/photo-1620916565856-d5d598e3bf1b?auto=format&fit=crop&w=1200&q=80',
  'GlowLab', array['clear'], array['30ml'], 'new'
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

-- Gallery images (cover + alternates)
insert into public.product_images (product_id, url, sort_order)
select p.id, imgs.url, imgs.sort_order
from public.products p
join lateral (
  values
    (p.cover_image_url, 0),
    (
      case p.slug
        when 'wireless-noise-canceling-headphones' then 'https://images.unsplash.com/photo-1484704849700-f032a568e944?auto=format&fit=crop&w=1200&q=80'
        when 'classic-linen-shirt' then 'https://images.unsplash.com/photo-1603252109303-110106195e9c?auto=format&fit=crop&w=1200&q=80'
        when 'everyday-cotton-tee' then 'https://images.unsplash.com/photo-1583743814966-8936f5b7be1a?auto=format&fit=crop&w=1200&q=80'
        when 'kids-graphic-hoodie' then 'https://images.unsplash.com/photo-1503919545889-aef636e10ad0?auto=format&fit=crop&w=1200&q=80'
        when 'ceramic-pour-over-set' then 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=1200&q=80'
        when 'running-trainers' then 'https://images.unsplash.com/photo-1606107557195-0e29a4b5b4aa?auto=format&fit=crop&w=1200&q=80'
        when 'minimal-leather-tote' then 'https://images.unsplash.com/photo-1548036328-c9fa89d128fa?auto=format&fit=crop&w=1200&q=80'
        when 'hydrating-face-serum' then 'https://images.unsplash.com/photo-1571781926291-c77df8097c5c?auto=format&fit=crop&w=1200&q=80'
        else p.cover_image_url
      end,
      1
    )
) as imgs(url, sort_order) on true
where p.slug in (
  'wireless-noise-canceling-headphones',
  'classic-linen-shirt',
  'everyday-cotton-tee',
  'kids-graphic-hoodie',
  'ceramic-pour-over-set',
  'running-trainers',
  'minimal-leather-tote',
  'hydrating-face-serum'
)
and not exists (
  select 1 from public.product_images pi
  where pi.product_id = p.id and pi.url = imgs.url
);
