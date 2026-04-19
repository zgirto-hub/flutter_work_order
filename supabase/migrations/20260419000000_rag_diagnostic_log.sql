-- Migration: rag_diagnostic_log table + RLS + indexes + pg_cron prune job
-- Feature: 088-rag-refusal-diagnostic

CREATE TABLE IF NOT EXISTS rag_diagnostic_log (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    user_email text NOT NULL,
    source text NOT NULL DEFAULT 'user'
        CHECK (source IN ('user', 'test_suite', 'internal')),
    question_raw text NOT NULL,
    decision text NOT NULL
        CHECK (decision IN ('grounded', 'ungrounded', 'error')),
    reason_code text NOT NULL
        CHECK (reason_code IN (
            'grounded_answer',
            'verbatim_answer',
            'short_circuited_no_rag',
            'no_chunks_retrieved',
            'rerank_below_threshold',
            'generator_refused_with_chunks',
            'pipeline_error'
        )),
    reason_note text,
    pipeline_stages jsonb NOT NULL DEFAULT '{}'::jsonb,
    thresholds jsonb NOT NULL DEFAULT '{}'::jsonb,
    latency_breakdown jsonb NOT NULL DEFAULT '{}'::jsonb,
    provider_used text,

    -- decision↔reason_code consistency: grounded decisions must use grounded codes
    CONSTRAINT rag_diagnostic_log_decision_reason_check
        CHECK ((decision = 'grounded') = (reason_code IN ('grounded_answer', 'verbatim_answer', 'short_circuited_no_rag')))
);

CREATE INDEX IF NOT EXISTS rag_diagnostic_log_filter_idx
    ON rag_diagnostic_log (source, decision, reason_code, created_at DESC);

CREATE INDEX IF NOT EXISTS rag_diagnostic_log_created_at_idx
    ON rag_diagnostic_log (created_at);

ALTER TABLE rag_diagnostic_log ENABLE ROW LEVEL SECURITY;

-- Idempotent policy creation: drop-and-recreate so repeat applies succeed.
DROP POLICY IF EXISTS rag_diagnostic_log_admin_select ON rag_diagnostic_log;
CREATE POLICY rag_diagnostic_log_admin_select ON rag_diagnostic_log
    FOR SELECT
    USING (auth.jwt() ->> 'role' = 'admin');

-- pg_cron retention job: asymmetric prune
-- Refused/errored entries: 30 days
-- Grounded entries: 7 days
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Idempotent schedule: unschedule existing job by name (if any) before re-registering,
-- otherwise cron.schedule inserts a duplicate row and fires the prune twice daily.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rag-diagnostic-prune') THEN
        PERFORM cron.unschedule('rag-diagnostic-prune');
    END IF;
END $$;

SELECT cron.schedule(
    'rag-diagnostic-prune',
    '15 3 * * *',
    $$DELETE FROM rag_diagnostic_log
      WHERE (decision IN ('ungrounded', 'error') AND created_at < now() - INTERVAL '30 days')
         OR (decision = 'grounded'                AND created_at < now() - INTERVAL '7 days')$$
);