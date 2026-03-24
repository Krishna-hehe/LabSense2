-- Align profiles schema with the Flutter app's multi-profile model.
-- Safe to run after legacy single-profile setups.

begin;

alter table public.profiles
  add column if not exists user_id uuid,
  add column if not exists phone_number text,
  add column if not exists state text,
  add column if not exists postal_code text,
  add column if not exists country text,
  add column if not exists email_notifications boolean not null default true,
  add column if not exists result_reminders boolean not null default true;

update public.profiles
set user_id = id
where user_id is null;

alter table public.profiles
  alter column user_id set not null;

do $$
declare
  fk_name text;
begin
  select con.conname
  into fk_name
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname = 'profiles'
    and con.contype = 'f'
    and pg_get_constraintdef(con.oid) like '%(id) REFERENCES auth.users(id)%';

  if fk_name is not null then
    execute format('alter table public.profiles drop constraint %I', fk_name);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'profiles'
      and con.conname = 'profiles_user_id_fkey'
  ) then
    alter table public.profiles
      add constraint profiles_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;
end $$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  username text;
begin
  username := coalesce(
    nullif(trim(new.raw_user_meta_data->>'first_name'), ''),
    'User'
  );

  insert into public.profiles (
    id,
    user_id,
    first_name,
    relationship,
    created_at,
    updated_at
  )
  values (
    new.id,
    new.id,
    username,
    'Self',
    now(),
    now()
  )
  on conflict (id) do update
    set user_id = excluded.user_id,
        first_name = coalesce(public.profiles.first_name, excluded.first_name),
        updated_at = now();

  return new;
exception
  when others then
    raise warning 'Failed to create profile for user %: %', new.id, sqlerrm;
    return new;
end;
$$;

drop policy if exists "Users can view their own profile." on public.profiles;
drop policy if exists "Users can insert their own profile." on public.profiles;
drop policy if exists "Users can update own profile." on public.profiles;

create policy "Users can view their own profile."
  on public.profiles
  for select
  using (auth.uid() = user_id);

create policy "Users can insert their own profile."
  on public.profiles
  for insert
  with check (auth.uid() = user_id);

create policy "Users can update own profile."
  on public.profiles
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

commit;
