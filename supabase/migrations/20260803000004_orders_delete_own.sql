-- Buyers can remove their own order history (items cascade)
drop policy if exists "orders_delete_own" on public.orders;
create policy "orders_delete_own"
  on public.orders for delete
  using (auth.uid() = buyer_id);
