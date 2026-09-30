-- gastos: per-user mirror of the on-device SwiftData store.
-- Rows are keyed by the client-generated UUID; `deleted` is a tombstone so deletes sync;
-- `updated_at` is always server time and is what clients pull by.

create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;

create table public.accounts (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null default '',
  type text not null default 'cash',
  opening_balance numeric not null default 0,
  currency text not null default 'PHP',
  icon text not null default '',
  color_hex text not null default '',
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

create table public.categories (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null default '',
  icon text not null default '',
  color_hex text not null default '',
  is_default boolean not null default false,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

create table public.entries (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type text not null default 'expense',
  amount numeric not null default 0,
  currency text not null default 'PHP',
  date timestamptz not null default now(),
  note text not null default '',
  account_id uuid,
  to_account_id uuid,
  category_id uuid,
  recurring_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

create table public.budgets (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  amount numeric not null default 0,
  period text not null default 'monthly',
  category_id uuid,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

create table public.recurring_transactions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null default '',
  amount numeric not null default 0,
  type text not null default 'expense',
  currency text not null default 'PHP',
  frequency text not null default 'monthly',
  start_date timestamptz not null default now(),
  posted_count integer not null default 0,
  is_active boolean not null default true,
  account_id uuid,
  category_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

do $$
declare t text;
begin
  foreach t in array array['accounts','categories','entries','budgets','recurring_transactions'] loop
    execute format('create trigger touch_updated_at before insert or update on public.%I
                    for each row execute function public.touch_updated_at()', t);
    execute format('create index %I on public.%I (user_id, updated_at)', t || '_user_updated_idx', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "own rows: select" on public.%I for select to authenticated using ((select auth.uid()) = user_id)', t);
    execute format('create policy "own rows: insert" on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)', t);
    execute format('create policy "own rows: update" on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t);
  end loop;
end $$;

-- In-app account deletion (App Store requirement). Removing the auth user cascades every row above.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
