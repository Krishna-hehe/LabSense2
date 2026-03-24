-- CRITICAL FIX: pgvector Extension Configuration
-- This migration fixes the "operator does not exist: extensions.vector <=> extensions.vector" error
-- Step 1: Ensure pgvector extension is enabled
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
-- Step 2: Drop the old function completely (all variants)
DROP FUNCTION IF EXISTS match_test_embeddings(extensions.vector, float, int);
DROP FUNCTION IF EXISTS match_test_embeddings(extensions.vector(768), float, int);
-- Step 3: Drop and recreate the test_embeddings table
DROP TABLE IF EXISTS public.test_embeddings CASCADE;
CREATE TABLE public.test_embeddings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    test_name text NOT NULL,
    content text NOT NULL,
    metadata jsonb,
    embedding extensions.vector(768),
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);
-- Step 4: Enable Row Level Security
ALTER TABLE public.test_embeddings ENABLE ROW LEVEL SECURITY;
-- Step 5: Create RLS policies
CREATE POLICY "Users can view their own embeddings" ON public.test_embeddings FOR
SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own embeddings" ON public.test_embeddings FOR
INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own embeddings" ON public.test_embeddings FOR DELETE USING (auth.uid() = user_id);
-- Step 6: Create the match function with CORRECT schema path
-- CRITICAL: Use 'public' schema explicitly, not 'extensions'
CREATE OR REPLACE FUNCTION public.match_test_embeddings (
        query_embedding extensions.vector(768),
        match_threshold float,
        match_count int
    ) RETURNS TABLE (
        id uuid,
        content text,
        metadata jsonb,
        similarity float
    ) LANGUAGE plpgsql STABLE -- CRITICAL: Set search_path to public, NOT extensions
SET search_path TO public,
    pg_temp AS $$ BEGIN RETURN QUERY
SELECT test_embeddings.id,
    test_embeddings.content,
    test_embeddings.metadata,
    -- Use the <=> operator for cosine distance
    1 - (test_embeddings.embedding <=> query_embedding) AS similarity
FROM public.test_embeddings
WHERE auth.uid() = test_embeddings.user_id
    AND 1 - (test_embeddings.embedding <=> query_embedding) > match_threshold
ORDER BY similarity DESC
LIMIT match_count;
END;
$$;
-- Step 7: Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON public.test_embeddings TO authenticated;
GRANT EXECUTE ON FUNCTION public.match_test_embeddings(extensions.vector(768), float, int) TO authenticated;
-- Step 8: Create indexes for performance
CREATE INDEX IF NOT EXISTS test_embeddings_user_id_idx ON public.test_embeddings(user_id);
-- Create vector index using ivfflat (requires pgvector)
CREATE INDEX IF NOT EXISTS test_embeddings_embedding_idx ON public.test_embeddings USING ivfflat (embedding extensions.vector_cosine_ops) WITH (lists = 100);
-- Migration complete
-- This should fix both the UUID mismatch AND the operator error
