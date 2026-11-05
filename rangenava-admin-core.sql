-- Rangenava Admin Core - Secure Phase 1
-- Additive migration. Existing music tables are untouched.

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'support'
    check (role in ('owner','music','artists','ads','support','content','news')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.page_views (
  id bigint generated always as identity primary key,
  path text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.artist_requests (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  artist_role text,
  email text,
  phone text,
  subject text,
  message text not null,
  portfolio_url text,
  status text not null default 'new'
    check (status in ('new','reviewing','answered','approved','rejected','closed')),
  admin_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ad_orders (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null,
  business_name text,
  email text,
  phone text,
  ad_type text not null,
  placement text,
  title text,
  description text,
  target_url text,
  start_date date,
  end_date date,
  budget numeric(14,2),
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid','pending','paid','refunded')),
  order_status text not null default 'new'
    check (order_status in ('new','reviewing','approved','running','completed','rejected','cancelled')),
  admin_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text,
  phone text,
  category text not null default 'general',
  subject text,
  message text not null,
  status text not null default 'new'
    check (status in ('new','in_progress','answered','closed')),
  admin_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_activity (
  id bigint generated always as identity primary key,
  admin_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Indexes
create index if not exists idx_page_views_created
on public.page_views(created_at desc);

create index if not exists idx_artist_requests_status
on public.artist_requests(status, created_at desc);

create index if not exists idx_ad_orders_status
on public.ad_orders(order_status, created_at desc);

create index if not exists idx_contact_messages_status
on public.contact_messages(status, created_at desc);

create index if not exists idx_admin_activity_created
on public.admin_activity(created_at desc);

-- Updated timestamps
create or replace function public.set_rangenava_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists artist_requests_updated_at on public.artist_requests;
create trigger artist_requests_updated_at
before update on public.artist_requests
for each row execute function public.set_rangenava_updated_at();

drop trigger if exists ad_orders_updated_at on public.ad_orders;
create trigger ad_orders_updated_at
before update on public.ad_orders
for each row execute function public.set_rangenava_updated_at();

drop trigger if exists contact_messages_updated_at on public.contact_messages;
create trigger contact_messages_updated_at
before update on public.contact_messages
for each row execute function public.set_rangenava_updated_at();

-- Admin verification
create or replace function public.rangenava_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users
    where user_id = (select auth.uid())
      and is_active = true
  );
$$;

-- Owner verification
create or replace function public.rangenava_is_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users
    where user_id = (select auth.uid())
      and is_active = true
      and role = 'owner'
  );
$$;

revoke all on function public.rangenava_is_admin() from public;
revoke all on function public.rangenava_is_owner() from public;

grant execute on function public.rangenava_is_admin() to authenticated;
grant execute on function public.rangenava_is_owner() to authenticated;

-- Enable RLS
alter table public.admin_users enable row level security;
alter table public.page_views enable row level security;
alter table public.artist_requests enable row level security;
alter table public.ad_orders enable row level security;
alter table public.contact_messages enable row level security;
alter table public.admin_activity enable row level security;

-- Remove old policies on these tables
drop policy if exists admin_users_read_self on public.admin_users;
drop policy if exists admin_users_manage on public.admin_users;
drop policy if exists page_views_public_insert on public.page_views;
drop policy if exists page_views_admin_read on public.page_views;

drop policy if exists artist_requests_public_insert on public.artist_requests;
drop policy if exists artist_requests_admin_read on public.artist_requests;
drop policy if exists artist_requests_admin_update on public.artist_requests;
drop policy if exists artist_requests_admin_delete on public.artist_requests;

drop policy if exists ad_orders_public_insert on public.ad_orders;
drop policy if exists ad_orders_admin_read on public.ad_orders;
drop policy if exists ad_orders_admin_update on public.ad_orders;
drop policy if exists ad_orders_admin_delete on public.ad_orders;

drop policy if exists contact_messages_public_insert on public.contact_messages;
drop policy if exists contact_messages_admin_read on public.contact_messages;
drop policy if exists contact_messages_admin_update on public.contact_messages;
drop policy if exists contact_messages_admin_delete on public.contact_messages;

drop policy if exists admin_activity_admin_read on public.admin_activity;
drop policy if exists admin_activity_admin_insert on public.admin_activity;

-- Admin accounts: only owner manages accounts
create policy admin_users_read_self
on public.admin_users
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.rangenava_is_owner()
);

create policy admin_users_manage
on public.admin_users
for all to authenticated
using (public.rangenava_is_owner())
with check (public.rangenava_is_owner());

-- Page views
create policy page_views_public_insert
on public.page_views
for insert to anon, authenticated
with check (
  length(path) between 1 and 300
  and path not like '%?%'
);

create policy page_views_admin_read
on public.page_views
for select to authenticated
using (public.rangenava_is_admin());

-- Artist requests
create policy artist_requests_public_insert
on public.artist_requests
for insert to anon, authenticated
with check (
  length(full_name) between 2 and 120
  and length(message) between 5 and 5000
);

create policy artist_requests_admin_read
on public.artist_requests
for select to authenticated
using (public.rangenava_is_admin());

create policy artist_requests_admin_update
on public.artist_requests
for update to authenticated
using (public.rangenava_is_admin())
with check (public.rangenava_is_admin());

create policy artist_requests_admin_delete
on public.artist_requests
for delete to authenticated
using (public.rangenava_is_admin());

-- Advertising orders
create policy ad_orders_public_insert
on public.ad_orders
for insert to anon, authenticated
with check (
  length(customer_name) between 2 and 120
  and length(ad_type) between 2 and 80
);

create policy ad_orders_admin_read
on public.ad_orders
for select to authenticated
using (public.rangenava_is_admin());

create policy ad_orders_admin_update
on public.ad_orders
for update to authenticated
using (public.rangenava_is_admin())
with check (public.rangenava_is_admin());

create policy ad_orders_admin_delete
on public.ad_orders
for delete to authenticated
using (public.rangenava_is_admin());

-- Contact messages
create policy contact_messages_public_insert
on public.contact_messages
for insert to anon, authenticated
with check (
  length(full_name) between 2 and 120
  and length(message) between 3 and 5000
);

create policy contact_messages_admin_read
on public.contact_messages
for select to authenticated
using (public.rangenava_is_admin());

create policy contact_messages_admin_update
on public.contact_messages
for update to authenticated
using (public.rangenava_is_admin())
with check (public.rangenava_is_admin());

create policy contact_messages_admin_delete
on public.contact_messages
for delete to authenticated
using (public.rangenava_is_admin());

-- Admin activity
create policy admin_activity_admin_read
on public.admin_activity
for select to authenticated
using (public.rangenava_is_admin());

create policy admin_activity_admin_insert
on public.admin_activity
for insert to authenticated
with check (
  public.rangenava_is_admin()
  and admin_user_id = (select auth.uid())
);

-- Explicit table permissions
revoke all on public.admin_users from public, anon, authenticated;
revoke all on public.page_views from public, anon, authenticated;
revoke all on public.artist_requests from public, anon, authenticated;
revoke all on public.ad_orders from public, anon, authenticated;
revoke all on public.contact_messages from public, anon, authenticated;
revoke all on public.admin_activity from public, anon, authenticated;

grant select on public.admin_users to authenticated;

grant insert on public.page_views to anon, authenticated;
grant select on public.page_views to authenticated;

grant insert on public.artist_requests to anon, authenticated;
grant select, update, delete on public.artist_requests to authenticated;

grant insert on public.ad_orders to anon, authenticated;
grant select, update, delete on public.ad_orders to authenticated;

grant insert on public.contact_messages to anon, authenticated;
grant select, update, delete on public.contact_messages to authenticated;

grant select, insert on public.admin_activity to authenticated;