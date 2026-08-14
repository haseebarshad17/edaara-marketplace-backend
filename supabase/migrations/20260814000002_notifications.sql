-- In-app inbox. Templates are the admin surface (slug + event); rows are what the user sees.
-- Admin later: insert a template with slug `store-welcome` and event `store.created`.

create table if not exists public.notification_templates (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  event text not null,
  audience text not null default 'seller'
    check (audience in ('seller', 'buyer', 'all')),
  type text not null default 'system'
    check (type in ('order', 'payout', 'listing', 'system')),
  title text not null,
  body text not null,
  href text,
  once_per_recipient boolean not null default false,
  cooldown_hours integer
    check (cooldown_hours is null or cooldown_hours >= 0),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists notification_templates_event_idx
  on public.notification_templates (event)
  where active;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  seller_id uuid references public.sellers (id) on delete set null,
  template_slug text references public.notification_templates (slug) on delete set null,
  event text not null,
  type text not null default 'system'
    check (type in ('order', 'payout', 'listing', 'system')),
  title text not null,
  body text not null,
  href text,
  read_at timestamptz,
  dismissed_at timestamptz,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists notifications_inbox_idx
  on public.notifications (user_id, created_at desc)
  where dismissed_at is null;

drop trigger if exists notification_templates_set_updated_at on public.notification_templates;
create trigger notification_templates_set_updated_at
before update on public.notification_templates
for each row execute function public.set_updated_at();

alter table public.notification_templates enable row level security;
alter table public.notifications enable row level security;

drop policy if exists notification_templates_select_active on public.notification_templates;
create policy notification_templates_select_active
  on public.notification_templates for select
  to authenticated
  using (active = true);

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own
  on public.notifications for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own
  on public.notifications for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.emit_notifications(
  p_event text,
  p_user_id uuid default null,
  p_seller_id uuid default null,
  p_meta jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient uuid := coalesce(p_user_id, auth.uid());
  seller uuid := p_seller_id;
  tpl record;
  is_seller boolean := false;
begin
  if recipient is null or p_event is null or btrim(p_event) = '' then
    return;
  end if;

  if seller is null then
    select id into seller
      from public.sellers
     where user_id = recipient
     limit 1;
  end if;

  is_seller := seller is not null;

  for tpl in
    select *
      from public.notification_templates
     where active
       and event = p_event
     order by sort_order, created_at
  loop
    if tpl.audience = 'seller' and not is_seller then
      continue;
    end if;

    if tpl.audience = 'buyer' and is_seller then
      continue;
    end if;

    if tpl.once_per_recipient and exists (
      select 1
        from public.notifications n
       where n.user_id = recipient
         and n.template_slug = tpl.slug
    ) then
      continue;
    end if;

    if tpl.cooldown_hours is not null and exists (
      select 1
        from public.notifications n
       where n.user_id = recipient
         and n.template_slug = tpl.slug
         and n.created_at > now() - make_interval(hours => tpl.cooldown_hours)
    ) then
      continue;
    end if;

    insert into public.notifications (
      user_id, seller_id, template_slug, event, type, title, body, href, meta
    ) values (
      recipient,
      seller,
      tpl.slug,
      tpl.event,
      tpl.type,
      tpl.title,
      tpl.body,
      tpl.href,
      coalesce(p_meta, '{}'::jsonb)
    );
  end loop;
end;
$$;

revoke all on function public.emit_notifications(text, uuid, uuid, jsonb) from public;
grant execute on function public.emit_notifications(text, uuid, uuid, jsonb)
  to authenticated, service_role;

create or replace function public.emit_store_created_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.emit_notifications('store.created', new.user_id, new.id, '{}'::jsonb);
  return new;
end;
$$;

drop trigger if exists sellers_emit_store_created on public.sellers;
create trigger sellers_emit_store_created
after insert on public.sellers
for each row execute function public.emit_store_created_notifications();

insert into public.notification_templates (
  slug, event, audience, type, title, body, href,
  once_per_recipient, cooldown_hours, sort_order
) values
  (
    'store-welcome',
    'store.created',
    'seller',
    'system',
    'Your store is ready',
    'eDaara is set up for your shop. List a few products and you will start showing up to buyers.',
    '/seller/products',
    true,
    null,
    10
  ),
  (
    'store-add-products',
    'store.created',
    'seller',
    'listing',
    'Add products to grow',
    'Stores with a handful of live listings get found. Start with what you already have in stock.',
    '/seller/products',
    true,
    null,
    20
  ),
  (
    'session-signin',
    'session.signin',
    'seller',
    'system',
    'Sign-in detected',
    'Someone signed in to your seller workspace. If this was not you, change your password in account settings.',
    '/account',
    false,
    24,
    30
  )
on conflict (slug) do nothing;
