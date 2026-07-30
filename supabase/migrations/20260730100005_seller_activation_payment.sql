-- 005_seller_activation_payment.sql
-- Seller goes live only after a paid seller_activation payment.

-- Users may update their own payment rows (e.g. pending) but cannot mark paid
-- except via finalizers (sets edaara.finalizing_payment).
drop policy if exists "payments_update_own" on public.payments;
create policy "payments_update_own"
  on public.payments for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.payments_guard_paid_status()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'paid'
     and (tg_op = 'INSERT' or old.status is distinct from 'paid') then
    if current_setting('edaara.finalizing_payment', true) is distinct from '1' then
      raise exception 'Payments can only be marked paid by the activation finalizer';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists payments_guard_paid_status on public.payments;
create trigger payments_guard_paid_status
before insert or update of status on public.payments
for each row execute function public.payments_guard_paid_status();

create or replace function public.finalize_seller_activation(p_basket_id text)
returns public.sellers
language plpgsql
security definer
set search_path = public
as $$
declare
  pay public.payments%rowtype;
  sel public.sellers%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if p_basket_id is null or length(trim(p_basket_id)) = 0 then
    raise exception 'Missing payment reference';
  end if;

  select * into pay
  from public.payments
  where provider_reference = p_basket_id
    and user_id = auth.uid()
    and purpose = 'seller_activation'
  for update;

  if not found then
    raise exception 'Payment not found';
  end if;

  if pay.status = 'failed' then
    raise exception 'Payment failed';
  end if;

  if pay.status = 'paid' then
    select * into sel
    from public.sellers
    where id = pay.seller_id and user_id = auth.uid();
    if not found then
      raise exception 'Seller not found for payment';
    end if;
    return sel;
  end if;

  -- Only sandbox mock OR provider-confirmed (webhook / verified return) may finalize.
  if coalesce(pay.raw_payload->>'sandbox_mock', 'false') <> 'true'
     and coalesce(pay.raw_payload->>'provider_confirmed', 'false') <> 'true' then
    raise exception 'Payment is not confirmed by PayFast yet';
  end if;

  perform set_config('edaara.finalizing_payment', '1', true);

  update public.payments
  set
    status = 'paid',
    raw_payload = coalesce(raw_payload, '{}'::jsonb) || jsonb_build_object(
      'finalized_at', now(),
      'finalized_by', 'finalize_seller_activation'
    )
  where id = pay.id;

  update public.sellers
  set
    status = 'active',
    activated_at = coalesce(activated_at, now())
  where id = pay.seller_id
    and user_id = auth.uid()
  returning * into sel;

  if not found then
    raise exception 'Seller not found for payment';
  end if;

  return sel;
end;
$$;

revoke all on function public.finalize_seller_activation(text) from public;
grant execute on function public.finalize_seller_activation(text) to authenticated;

-- Sandbox-only confirm (requires raw_payload.sandbox_mock = true).
create or replace function public.confirm_seller_activation_payment(
  p_basket_id text,
  p_payload jsonb default '{}'::jsonb
)
returns public.sellers
language plpgsql
security definer
set search_path = public
as $$
declare
  pay public.payments%rowtype;
  sel public.sellers%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select * into pay
  from public.payments
  where provider_reference = p_basket_id
    and purpose = 'seller_activation'
    and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'Payment not found';
  end if;

  if coalesce(pay.raw_payload->>'sandbox_mock', 'false') <> 'true' then
    raise exception 'Sandbox confirm is only allowed for mock PayFast checkouts';
  end if;

  if pay.status = 'paid' then
    select * into sel from public.sellers where id = pay.seller_id and user_id = auth.uid();
    return sel;
  end if;

  perform set_config('edaara.finalizing_payment', '1', true);

  update public.payments
  set
    status = 'paid',
    raw_payload = coalesce(raw_payload, '{}'::jsonb)
      || coalesce(p_payload, '{}'::jsonb)
      || jsonb_build_object(
        'provider_confirmed', true,
        'sandbox_confirmed', true,
        'confirmed_at', now()
      )
  where id = pay.id;

  update public.sellers
  set
    status = 'active',
    activated_at = coalesce(activated_at, now())
  where id = pay.seller_id
    and user_id = auth.uid()
  returning * into sel;

  if not found then
    raise exception 'Seller not found for payment';
  end if;

  return sel;
end;
$$;

revoke all on function public.confirm_seller_activation_payment(text, jsonb) from public;
grant execute on function public.confirm_seller_activation_payment(text, jsonb) to authenticated;

-- Block setting sellers.status = active unless a matching paid payment exists.
create or replace function public.sellers_require_paid_activation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'active'
     and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    if not exists (
      select 1
      from public.payments p
      where p.seller_id = new.id
        and p.purpose = 'seller_activation'
        and p.status = 'paid'
    ) then
      raise exception 'Seller activation requires a paid PayFast payment';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists sellers_require_paid_activation on public.sellers;
create trigger sellers_require_paid_activation
before insert or update of status on public.sellers
for each row execute function public.sellers_require_paid_activation();
