-- Order payment finalizer must set edaara.finalizing_payment (same as seller activation)
-- so payments_guard_paid_status allows status = 'paid'.

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
  uid uuid := auth.uid();
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

  -- Service role may finalize any; logged-in users only their own.
  if uid is not null and v_payment.user_id is distinct from uid then
    raise exception 'Payment does not belong to this user';
  end if;

  if v_payment.order_id is null then
    raise exception 'Payment is not linked to an order';
  end if;

  -- Already finalized — return order as-is
  if v_payment.status = 'paid' then
    select * into v_order from public.orders where id = v_payment.order_id;
    return v_order;
  end if;

  -- Required by payments_guard_paid_status trigger
  perform set_config('edaara.finalizing_payment', '1', true);

  update public.payments
  set
    status = 'paid',
    raw_payload = coalesce(raw_payload, '{}'::jsonb)
      || coalesce(p_payload, '{}'::jsonb)
      || jsonb_build_object(
        'provider_confirmed', true,
        'verified_at', now()
      ),
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
