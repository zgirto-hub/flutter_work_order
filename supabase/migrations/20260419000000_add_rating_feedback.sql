-- Spec 087: thumbs-down reason and comment capture.
-- Adds two nullable columns to answer_ratings. Both stay NULL for:
--   * all existing rows (no backfill)
--   * all thumbs-up ratings
--   * thumbs-down ratings where the rater skipped the feedback prompt

ALTER TABLE answer_ratings
  ADD COLUMN IF NOT EXISTS feedback_reason TEXT
    CHECK (feedback_reason IN ('inaccurate', 'incomplete', 'outdated', 'wrong_source', 'unclear')),
  ADD COLUMN IF NOT EXISTS feedback_comment TEXT;