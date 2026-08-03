-- Supabase forbids DELETE on storage.objects from SQL triggers.
-- Cleanup must use the Storage API (app / service role). Drop the broken triggers.

drop trigger if exists product_review_images_delete_storage on public.product_review_images;
drop trigger if exists product_images_delete_storage on public.product_images;
drop trigger if exists products_cleanup_cover_storage on public.products;
drop trigger if exists profiles_delete_storage_folders on public.profiles;

drop function if exists public.trg_product_review_images_delete_storage();
drop function if exists public.trg_product_images_delete_storage();
drop function if exists public.trg_products_cleanup_cover_storage();
drop function if exists public.trg_profiles_delete_storage_folders();

-- Keep list_* RPCs for account-delete API. Drop SQL deleters that hit storage.objects.
drop function if exists public.delete_storage_object_by_public_url(text, text);
drop function if exists public.delete_storage_folder(text, uuid);
