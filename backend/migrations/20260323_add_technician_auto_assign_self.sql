-- Add technician_auto_assign_self column to notification_preferences
-- When enabled, a technician is automatically assigned to work orders they create.

ALTER TABLE notification_preferences
    ADD COLUMN IF NOT EXISTS technician_auto_assign_self BOOLEAN DEFAULT false;

-- Ensure user_email has a unique constraint so upserts with on_conflict="user_email" work.
-- (The PK was moved to user_id in notification_user_id_migration, leaving user_email without a unique constraint.)
ALTER TABLE notification_preferences
    ADD CONSTRAINT IF NOT EXISTS notification_preferences_user_email_unique UNIQUE (user_email);
