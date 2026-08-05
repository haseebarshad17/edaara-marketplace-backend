-- Fix contact_inquiries RLS: allow public inserts; select only own rows

drop policy if exists contact_inquiries_insert_public on public.contact_inquiries;
create policy contact_inquiries_insert_public
  on public.contact_inquiries
  for insert
  to anon, authenticated
  with check (
    user_id is null
    or user_id = auth.uid()
  );

grant insert on public.contact_inquiries to anon, authenticated;
grant select on public.contact_inquiries to authenticated;
