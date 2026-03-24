-- Security self-test helpers
-- Verifies access control posture of core PHI tables from authenticated context.

create or replace function public.security_self_test()
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  rogue_id uuid := '00000000-0000-0000-0000-000000000000';
  lab_count integer := 0;
  profile_count integer := 0;
  prescription_count integer := 0;
  medication_count integer := 0;
  reminders_count integer := 0;
  lab_rls_enabled boolean := false;
  profiles_rls_enabled boolean := false;
  prescriptions_rls_enabled boolean := false;
  medications_rls_enabled boolean := true;
  reminders_rls_enabled boolean := true;
  has_medications_table boolean := false;
  has_reminder_table boolean := false;
begin
  if auth.uid() is null then
    raise exception 'security_self_test requires an authenticated session';
  end if;

  select count(*) into lab_count
  from public.lab_results
  where user_id = rogue_id;
  select c.relrowsecurity into lab_rls_enabled
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'lab_results';

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'user_id'
  ) then
    execute
      'select count(*) from public.profiles where user_id = $1'
      into profile_count
      using rogue_id;
  else
    execute
      'select count(*) from public.profiles where id = $1'
      into profile_count
      using rogue_id;
  end if;
  select c.relrowsecurity into profiles_rls_enabled
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'profiles';

  select count(*) into prescription_count
  from public.prescriptions
  where user_id = rogue_id;
  select c.relrowsecurity into prescriptions_rls_enabled
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'prescriptions';

  select to_regclass('public.medications') is not null into has_medications_table;
  if has_medications_table then
    select count(*) into medication_count
    from public.medications
    where user_id = rogue_id;

    select c.relrowsecurity into medications_rls_enabled
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'medications';
  end if;

  select to_regclass('public.reminder_schedules') is not null into has_reminder_table;
  if has_reminder_table and has_medications_table then
    execute
      'select count(*) from public.reminder_schedules rs
       join public.medications m on m.id = rs.medication_id
       where m.user_id = $1'
      into reminders_count
      using rogue_id;

    select c.relrowsecurity into reminders_rls_enabled
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'reminder_schedules';
  end if;

  return jsonb_build_object(
    'ok',
    (lab_count = 0
      and profile_count = 0
      and prescription_count = 0
      and medication_count = 0
      and (not has_reminder_table or reminders_count = 0)
      and lab_rls_enabled
      and profiles_rls_enabled
      and prescriptions_rls_enabled
      and medications_rls_enabled
      and reminders_rls_enabled),
    'lab_results_count', lab_count,
    'profiles_count', profile_count,
    'prescriptions_count', prescription_count,
    'medications_count', medication_count,
    'reminders_count', reminders_count,
    'lab_results_rls', lab_rls_enabled,
    'profiles_rls', profiles_rls_enabled,
    'prescriptions_rls', prescriptions_rls_enabled,
    'medications_rls', medications_rls_enabled,
    'reminders_rls', reminders_rls_enabled
  );
end;
$$;

grant execute on function public.security_self_test() to authenticated;
