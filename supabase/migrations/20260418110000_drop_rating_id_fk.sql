-- Spec 080 follow-up: drop FK on validated_qa.rating_id so Train AI can
-- insert synthetic grouping UUIDs (primary + variants share the same
-- rating_id for cascade delete without needing a real answer_ratings row).

ALTER TABLE validated_qa
  DROP CONSTRAINT IF EXISTS validated_qa_rating_id_fkey;
