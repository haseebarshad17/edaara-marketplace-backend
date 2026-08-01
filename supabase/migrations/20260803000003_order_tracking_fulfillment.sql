-- Public tracking codes + richer fulfillment statuses for buyer track / seller update

-- Extend order status for packing → out for delivery → shipped
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders
  add constraint orders_status_check
  check (status in (
    'pending_payment',
    'paid',
    'processing',
    'packed',
    'out_for_delivery',
    'shipped',
    'delivered',
    'cancelled',
    'refunded'
  ));

alter table public.orders
  add column if not exists tracking_code text;

create unique index if not exists orders_tracking_code_uidx
  on public.orders (tracking_code)
  where tracking_code is not null;

-- Backfill codes for existing orders
update public.orders
set tracking_code = 'EDA-' || upper(substr(replace(id::text, '-', ''), 1, 8))
where tracking_code is null;

-- Sellers may update fulfillment on orders that include their line items
drop policy if exists "orders_update_as_seller" on public.orders;
create policy "orders_update_as_seller"
  on public.orders for update
  using (
    exists (
      select 1
      from public.order_items oi
      join public.sellers s on s.id = oi.seller_id
      where oi.order_id = orders.id
        and s.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.order_items oi
      join public.sellers s on s.id = oi.seller_id
      where oi.order_id = orders.id
        and s.user_id = auth.uid()
    )
  );

-- Public track lookup (limited fields — no full street address)
create or replace function public.track_order_by_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_items jsonb;
  v_city text;
begin
  if p_code is null or length(trim(p_code)) < 4 then
    raise exception 'Enter a valid tracking code';
  end if;

  select * into v_order
  from public.orders
  where upper(tracking_code) = upper(trim(p_code))
  limit 1;

  if not found then
    raise exception 'No order found for that tracking code';
  end if;

  select coalesce(
    (v_order.shipping_address->>'city'),
    null
  ) into v_city;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'title', oi.title,
        'quantity', oi.quantity,
        'line_total_pkr', oi.line_total_pkr
      )
      order by oi.title
    ),
    '[]'::jsonb
  )
  into v_items
  from public.order_items oi
  where oi.order_id = v_order.id;

  return jsonb_build_object(
    'tracking_code', v_order.tracking_code,
    'status', v_order.status,
    'payment_method', v_order.payment_method,
    'currency', v_order.currency,
    'total_pkr', v_order.total_pkr,
    'city', v_city,
    'created_at', v_order.created_at,
    'updated_at', v_order.updated_at,
    'items', v_items
  );
end;
$$;

revoke all on function public.track_order_by_code(text) from public;
grant execute on function public.track_order_by_code(text) to anon, authenticated, service_role;
