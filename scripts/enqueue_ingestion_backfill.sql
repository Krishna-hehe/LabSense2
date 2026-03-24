-- Enqueue historical reports for re-indexing after vector model/schema changes.
-- Run this after applying queue migration and before/after processor worker rollout.

insert into public.ingestion_jobs (
  user_id,
  source_doc_id,
  storage_path,
  file_name,
  file_mime_type,
  status,
  stage,
  progress,
  payload
)
select
  lr.user_id,
  lr.id as source_doc_id,
  lr.storage_path,
  coalesce(nullif(split_part(lr.storage_path, '/', 2), ''), 'lab_report.pdf') as file_name,
  'application/pdf' as file_mime_type,
  'queued' as status,
  'queued' as stage,
  0 as progress,
  jsonb_build_object('reason', 'historical_backfill') as payload
from public.lab_results lr
where lr.storage_path is not null
  and lr.storage_path <> ''
  and not exists (
    select 1
    from public.ingestion_jobs ij
    where ij.user_id = lr.user_id
      and ij.storage_path = lr.storage_path
      and ij.status in ('queued', 'processing', 'done')
  );
