-- Add generated_date column and unique index to prevent duplicate generation per day.
-- The unique index on (recurring_inspection_id, generated_date) provides DB-level
-- protection against race conditions in the generate endpoint.

ALTER TABLE recurring_inspection_logs
  ADD COLUMN generated_date DATE NOT NULL DEFAULT CURRENT_DATE;

CREATE UNIQUE INDEX recurring_inspection_logs_unique_per_day
  ON recurring_inspection_logs (recurring_inspection_id, generated_date);
