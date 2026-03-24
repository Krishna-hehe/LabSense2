-- Enable the pgvector extension to work with embeddings
create extension if not exists vector;

-- Create a table to store chunk-level lab report embeddings
create table if not exists public.test_embeddings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  test_name text not null,
  content text not null,
  metadata jsonb,
  chunk_index integer default 0,
  embedding vector(2048),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.test_embeddings enable row level security;

create policy "Users can view their own embeddings" on public.test_embeddings for
select using (auth.uid() = user_id);

create policy "Users can insert their own embeddings" on public.test_embeddings for
insert with check (auth.uid() = user_id);

drop function if exists public.match_test_embeddings;
create or replace function public.match_test_embeddings (
    query_embedding vector(2048),
    match_threshold float,
    match_count int
  ) returns table (
    id uuid,
    content text,
    metadata jsonb,
    similarity float
  ) language plpgsql stable
set search_path to public,
  pg_temp as $$ begin return query
select test_embeddings.id,
  test_embeddings.content,
  test_embeddings.metadata,
  1 - (test_embeddings.embedding <=> query_embedding) as similarity
from test_embeddings
where auth.uid() = test_embeddings.user_id
  and 1 - (test_embeddings.embedding <=> query_embedding) > match_threshold
order by similarity desc
limit match_count;
end;
$$;

drop index if exists public.test_embeddings_embedding_idx;
create index if not exists test_embeddings_embedding_idx
  on public.test_embeddings
  using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);
