-- Nemotron migration: 768-dim NIM vectors -> 2048-dim Nemotron vectors
-- Plus chunk indexing support for multi-chunk report retrieval.

create extension if not exists vector with schema extensions;

alter table public.test_embeddings
  add column if not exists chunk_index integer default 0;

-- Existing 768-dim rows must be cleared before changing vector dimensions.
update public.test_embeddings set embedding = null;

-- Drop ANN index before changing vector dimensions.
drop index if exists public.test_embeddings_embedding_idx;

alter table public.test_embeddings
  alter column embedding type extensions.vector(2048);

-- NOTE: Do not recreate ivfflat/hnsw ANN index for 2048-dim vectors.
-- pgvector ANN indexes support up to 2000 dimensions.

drop function if exists public.match_test_embeddings(extensions.vector(768), float, int);
drop function if exists public.match_test_embeddings(extensions.vector, float, int);

create or replace function public.match_test_embeddings (
    query_embedding extensions.vector(2048),
    match_threshold float,
    match_count int
  ) returns table (
    id uuid,
    content text,
    metadata jsonb,
    similarity float
  ) language plpgsql stable
set search_path to public,
  pg_temp as $$
begin
  return query
  select test_embeddings.id,
    test_embeddings.content,
    test_embeddings.metadata,
    1 - (test_embeddings.embedding <=> query_embedding) as similarity
  from public.test_embeddings
  where auth.uid() = test_embeddings.user_id
    and 1 - (test_embeddings.embedding <=> query_embedding) > match_threshold
  order by similarity desc
  limit match_count;
end;
$$;

grant execute on function public.match_test_embeddings(extensions.vector(2048), float, int) to authenticated;

