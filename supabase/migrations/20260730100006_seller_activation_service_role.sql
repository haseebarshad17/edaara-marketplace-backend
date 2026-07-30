-- Allows Next.js (service role) to confirm a PayFast-verified activation.
create or replace function public.activate_seller_payment_verified(
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
  select * into pay
  from public.payments
  where provider_reference = p_basket_id
    and purpose = 'seller_activation'
  for update;

  if not found then
    raise exception 'Payment not found';
  end if;

  if pay.status = 'paid' then
    select * into sel from public.sellers where id = pay.seller_id;
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
        'verified_at', now()
      )
  where id = pay.id;

  update public.sellers
  set
    status = 'active',
    activated_at = coalesce(activated_at, now())
  where id = pay.seller_id
  returning * into sel;

  if not found then
    raise exception 'Seller not found for payment';
  end if;

  return sel;
end;
$$;

revoke all on function public.activate_seller_payment_verified(text, jsonb) from public;
grant execute on function public.activate_seller_payment_verified(text, jsonb) to service_role;
