-- Backend hardening: ingestion queue + retries + dead-letter support

create table if not exists public.ingestion_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_doc_id uuid references public.lab_results(id) on delete set null,
  storage_path text not null,
  file_name text not null,
  file_mime_type text,
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'done', 'error', 'dead_letter')),
  stage text not null default 'queued',
  progress integer not null default 0 check (progress >= 0 and progress <= 100),
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5 check (max_attempts > 0),
  last_error text,
  payload jsonb not null default '{}'::jsonb,
  parsed_data jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  started_at timestamptz,
  completed_at timestamptz
);

create index if not exists ingestion_jobs_user_status_idx
  on public.ingestion_jobs (user_id, status, created_at desc);

create unique index if not exists ingestion_jobs_active_path_uniq
  on public.ingestion_jobs (user_id, storage_path)
  where status in ('queued', 'processing');

create index if not exists ingestion_jobs_status_idx
  on public.ingestion_jobs (status, created_at asc);

alter table public.ingestion_jobs enable row level security;

create policy "Users can view their own ingestion jobs"
  on public.ingestion_jobs
  for select
  using (auth.uid() = user_id);

create policy "Users can create their own ingestion jobs"
  on public.ingestion_jobs
  for insert
  with check (auth.uid() = user_id);

create table if not exists public.ingestion_dead_letters (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references public.ingestion_jobs(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null,
  file_name text not null,
  attempts integer not null,
  reason text not null,
  payload jsonb not null default '{}'::jsonb,
  moved_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists ingestion_dead_letters_user_idx
  on public.ingestion_dead_letters (user_id, moved_at desc);

alter table public.ingestion_dead_letters enable row level security;

create policy "Users can view their own dead-letter jobs"
  on public.ingestion_dead_letters
  for select
  using (auth.uid() = user_id);
