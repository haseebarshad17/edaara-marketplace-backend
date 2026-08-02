-- Delete storage objects when reviews / products / profiles go away.
-- Cascade already removes DB rows; this cleans the buckets that hold the bytes.

-- ——— Helpers ———

create or replace function public.storage_object_path_from_public_url(
  p_bucket text,
  p_url text
)
returns text
language plpgsql
immutable
as $$
declare
  marker text;
  pos integer;
  path text;
begin
  if p_bucket is null or p_url is null or length(trim(p_url)) = 0 then
    return null;
  end if;

  marker := '/object/public/' || p_bucket || '/';
  pos := position(marker in p_url);
  if pos = 0 then
    -- Also support /storage/v1/object/public/<bucket>/
    marker := '/storage/v1/object/public/' || p_bucket || '/';
    pos := position(marker in p_url);
    if pos = 0 then
      return null;
    end if;
  end if;

  path := substring(p_url from pos + length(marker));
  -- Strip query/hash if present
  path := split_part(path, '?', 1);
  path := split_part(path, '#', 1);
  if length(path) = 0 then
    return null;
  end if;
  return path;
end;
$$;

create or replace function public.delete_storage_object_by_public_url(
  p_bucket text,
  p_url text
)
returns void
language plpgsql
security definer
set search_path = storage, public
as $$
declare
  object_path text;
begin
  object_path := public.storage_object_path_from_public_url(p_bucket, p_url);
  if object_path is null then
    return;
  end if;

  delete from storage.objects
  where bucket_id = p_bucket
    and name = object_path;
end;
$$;

revoke all on function public.delete_storage_object_by_public_url(text, text) from public;
grant execute on function public.delete_storage_object_by_public_url(text, text) to service_role;

create or replace function public.delete_storage_folder(
  p_bucket text,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = storage, public
as $$
begin
  if p_bucket is null or p_user_id is null then
    return;
  end if;

  delete from storage.objects
  where bucket_id = p_bucket
    and (storage.foldername(name))[1] = p_user_id::text;
end;
$$;

revoke all on function public.delete_storage_folder(text, uuid) from public;
grant execute on function public.delete_storage_folder(text, uuid) to service_role;

-- List helpers for account-delete API (service role)
create or replace function public.list_review_image_object_paths(p_user_id uuid)
returns text[]
language sql
security definer
set search_path = storage, public
as $$
  select coalesce(array_agg(name order by name), '{}'::text[])
  from storage.objects
  where bucket_id = 'review-images'
    and (storage.foldername(name))[1] = p_user_id::text;
$$;

revoke all on function public.list_review_image_object_paths(uuid) from public;
grant execute on function public.list_review_image_object_paths(uuid) to service_role;

create or replace function public.list_product_image_object_paths(p_user_id uuid)
returns text[]
language sql
security definer
set search_path = storage, public
as $$
  select coalesce(array_agg(name order by name), '{}'::text[])
  from storage.objects
  where bucket_id = 'product-images'
    and (storage.foldername(name))[1] = p_user_id::text;
$$;

revoke all on function public.list_product_image_object_paths(uuid) from public;
grant execute on function public.list_product_image_object_paths(uuid) to service_role;

-- ——— Product images bucket (seller / admin uploads) ———

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "product_images_public_read" on storage.objects;
create policy "product_images_public_read"
  on storage.objects for select
  using (bucket_id = 'product-images');

drop policy if exists "product_images_auth_upload" on storage.objects;
create policy "product_images_auth_upload"
  on storage.objects for insert
  with check (
    bucket_id = 'product-images'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "product_images_auth_update" on storage.objects;
create policy "product_images_auth_update"
  on storage.objects for update
  using (
    bucket_id = 'product-images'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "product_images_auth_delete" on storage.objects;
create policy "product_images_auth_delete"
  on storage.objects for delete
  using (
    bucket_id = 'product-images'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ——— Triggers: review photos ———

create or replace function public.trg_product_review_images_delete_storage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.delete_storage_object_by_public_url('review-images', old.url);
  return old;
end;
$$;

drop trigger if exists product_review_images_delete_storage on public.product_review_images;
create trigger product_review_images_delete_storage
before delete on public.product_review_images
for each row execute function public.trg_product_review_images_delete_storage();

-- ——— Triggers: product gallery rows ———

create or replace function public.trg_product_images_delete_storage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.delete_storage_object_by_public_url('product-images', old.url);
  return old;
end;
$$;

drop trigger if exists product_images_delete_storage on public.product_images;
create trigger product_images_delete_storage
before delete on public.product_images
for each row execute function public.trg_product_images_delete_storage();

-- ——— Triggers: product cover image ———

create or replace function public.trg_products_cleanup_cover_storage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.delete_storage_object_by_public_url('product-images', old.cover_image_url);
    return old;
  end if;

  -- UPDATE: remove previous cover only when replaced or cleared
  if old.cover_image_url is distinct from new.cover_image_url then
    perform public.delete_storage_object_by_public_url('product-images', old.cover_image_url);
  end if;
  return new;
end;
$$;

drop trigger if exists products_cleanup_cover_storage on public.products;
create trigger products_cleanup_cover_storage
before update of cover_image_url or delete on public.products
for each row execute function public.trg_products_cleanup_cover_storage();

-- ——— Triggers: profile / account wipe storage folders ———
-- Cascades remove review image rows (and their triggers). This also clears
-- orphaned uploads and the whole avatars / review-images / product-images folders.

create or replace function public.trg_profiles_delete_storage_folders()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.delete_storage_folder('avatars', old.id);
  perform public.delete_storage_folder('review-images', old.id);
  perform public.delete_storage_folder('product-images', old.id);
  return old;
end;
$$;

drop trigger if exists profiles_delete_storage_folders on public.profiles;
create trigger profiles_delete_storage_folders
before delete on public.profiles
for each row execute function public.trg_profiles_delete_storage_folders();
