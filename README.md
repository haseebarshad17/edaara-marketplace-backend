# Marketplace backend (Supabase)

SQL lives here. **Files on disk do not create tables until you run them** in Supabase
(or via CLI with a DB password). The publishable/anon key cannot apply DDL.

## Apply now (fastest)

1. Open SQL Editor:  
   https://supabase.com/dashboard/project/iycmjqhfxzyqaxljiupz/sql/new
2. Open `supabase/APPLY_ALL.sql` in this repo, copy **everything**, paste into the editor
3. Click **Run**
4. Confirm under **Table Editor**: `profiles`, `addresses`, `sellers`, `categories`,
   `products`, `product_images`, `orders`, `order_items`, `payments`

Or run numbered files in order: `migrations/001` → `004`.

## Why you saw `PGRST205`

PostgREST could not find `public.profiles` because the table was never created in
the remote project. After `APPLY_ALL.sql` succeeds, reload the app and try again.

## Optional: CLI later

If you have the database password (Project Settings → Database):

```bash
cd backend
npx supabase link --project-ref iycmjqhfxzyqaxljiupz
npx supabase db push
```

## Payment / roles

- Checkout + seller activation (2,000 PKR) → PayFast (PKR)
- Buyer: shop routes · Seller: `/seller/*` in same Next app · Admin: later
