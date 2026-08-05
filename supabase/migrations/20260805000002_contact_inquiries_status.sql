-- Contact inquiries table + RLS (idempotent)
-- Note: 20260805000001 may already be recorded remotely without this table.

create table if not exists public.contact_inquiries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  name text not null,
  email text not null,
  subject text not null,
  message text not null,
  status text not null default 'new'
    check (status in ('new', 'open', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.contact_inquiries
  add column if not exists status text not null default 'new';

alter table public.contact_inquiries
  add column if not exists updated_at timestamptz not null default now();

create index if not exists contact_inquiries_created_at_idx
  on public.contact_inquiries (created_at desc);

create index if not exists contact_inquiries_status_idx
  on public.contact_inquiries (status);

create index if not exists contact_inquiries_user_id_idx
  on public.contact_inquiries (user_id)
  where user_id is not null;

drop trigger if exists contact_inquiries_set_updated_at on public.contact_inquiries;
create trigger contact_inquiries_set_updated_at
before update on public.contact_inquiries
for each row execute function public.set_updated_at();

alter table public.contact_inquiries enable row level security;

grant insert on public.contact_inquiries to anon, authenticated;
grant select on public.contact_inquiries to authenticated;

drop policy if exists contact_inquiries_insert_public on public.contact_inquiries;
create policy contact_inquiries_insert_public
  on public.contact_inquiries
  for insert
  to anon, authenticated
  with check (
    (user_id is null and auth.uid() is null)
    or (user_id = auth.uid())
  );

drop policy if exists contact_inquiries_select_own on public.contact_inquiries;
create policy contact_inquiries_select_own
  on public.contact_inquiries
  for select
  to authenticated
  using (auth.uid() = user_id);
