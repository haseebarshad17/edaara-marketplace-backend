-- Store-level settings the seller Settings page actually surfaces:
-- policies, payout details, and order/stock notification preferences.

alter table public.sellers
  add column if not exists shipping_policy text,
  add column if not exists return_policy text,
  add column if not exists payout_method text
    check (payout_method is null or payout_method in ('bank_transfer', 'jazzcash', 'easypaisa')),
  add column if not exists payout_account_name text,
  add column if not exists payout_account_number text,
  add column if not exists notify_new_order boolean not null default true,
  add column if not exists notify_low_stock boolean not null default true;
