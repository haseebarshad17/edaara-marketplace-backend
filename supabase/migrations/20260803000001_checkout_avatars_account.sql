-- Checkout payment method, avatars storage, account-deletion cascades

-- Orders: COD vs Safepay
alter table public.orders
  add column if not exists payment_method text
    check (payment_method is null or payment_method in ('safepay', 'cod'));

-- Allow deleting a buyer account (GDPR-style) without blocking on order history
do $$
begin
  if exists (
    select 1 from information_schema.table_constraints
    where constraint_schema = 'public'
      and table_name = 'orders'
      and constraint_name = 'orders_buyer_id_fkey'
  ) then
    alter table public.orders drop constraint orders_buyer_id_fkey;
  end if;
end $$;

alter table public.orders
  add constraint orders_buyer_id_fkey
  foreign key (buyer_id) references public.profiles (id) on delete cascade;

do $$
begin
  if exists (
    select 1 from information_schema.table_constraints
    where constraint_schema = 'public'
      and table_name = 'payments'
      and constraint_name = 'payments_user_id_fkey'
  ) then
    alter table public.payments drop constraint payments_user_id_fkey;
  end if;
end $$;

alter table public.payments
  add constraint payments_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;

-- Mark Safepay order payment paid + order paid
create or replace function public.activate_order_payment_verified(
  p_basket_id text,
  p_payload jsonb default '{}'::jsonb
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
  v_order public.orders%rowtype;
begin
  if p_basket_id is null or length(trim(p_basket_id)) = 0 then
    raise exception 'Missing payment tracker';
  end if;

  select * into v_payment
  from public.payments
  where purpose = 'order'
    and provider_reference = p_basket_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Order payment not found for tracker';
  end if;

  if v_payment.order_id is null then
    raise exception 'Payment is not linked to an order';
  end if;

  update public.payments
  set
    status = 'paid',
    raw_payload = coalesce(raw_payload, '{}'::jsonb) || coalesce(p_payload, '{}'::jsonb),
    updated_at = now()
  where id = v_payment.id;

  update public.orders
  set
    status = 'paid',
    payment_method = 'safepay',
    updated_at = now()
  where id = v_payment.order_id
  returning * into v_order;

  return v_order;
end;
$$;

revoke all on function public.activate_order_payment_verified(text, jsonb) from public;
grant execute on function public.activate_order_payment_verified(text, jsonb) to authenticated, service_role;

-- Ensure only one default address per user
create or replace function public.addresses_enforce_single_default()
returns trigger
language plpgsql
as $$
begin
  if new.is_default is true then
    update public.addresses
    set is_default = false
    where user_id = new.user_id
      and id is distinct from new.id
      and is_default = true;
  end if;
  return new;
end;
$$;

drop trigger if exists addresses_single_default on public.addresses;
create trigger addresses_single_default
before insert or update of is_default on public.addresses
for each row execute function public.addresses_enforce_single_default();

-- Avatars bucket (public read, owner write)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "avatars_owner_insert" on storage.objects;
create policy "avatars_owner_insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_owner_update" on storage.objects;
create policy "avatars_owner_update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_owner_delete" on storage.objects;
create policy "avatars_owner_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Service-role helper: list avatar object paths for a user (API deletes storage before auth.users)
create or replace function public.list_avatar_object_paths(p_user_id uuid)
returns text[]
language sql
security definer
set search_path = storage, public
as $$
  select coalesce(
    array_agg(name order by name),
    '{}'::text[]
  )
  from storage.objects
  where bucket_id = 'avatars'
    and (storage.foldername(name))[1] = p_user_id::text;
$$;

revoke all on function public.list_avatar_object_paths(uuid) from public;
grant execute on function public.list_avatar_object_paths(uuid) to service_role;
