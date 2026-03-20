-- =============================================================
-- Notification Schema Migration - Add user_id FK
-- Run in Supabase SQL Editor
-- =============================================================

-- STEP 1: Add new columns
ALTER TABLE notification_preferences ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id);
ALTER TABLE notification_preferences ADD COLUMN IF NOT EXISTS user_email_new text;
ALTER TABLE work_order_watchers ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id);
ALTER TABLE work_order_watchers ADD COLUMN IF NOT EXISTS user_email_new text;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id);
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS user_email_new text;
ALTER TABLE notification_delivery_logs ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id);
ALTER TABLE notification_delivery_logs ADD COLUMN IF NOT EXISTS user_email_new text;

-- STEP 2: Add FK constraint to work_order_watchers for work_order_id
ALTER TABLE work_order_watchers DROP CONSTRAINT IF EXISTS fk_watchers_work_order;
ALTER TABLE work_order_watchers ADD CONSTRAINT fk_watchers_work_order 
  FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;

-- STEP 3: Backfill user_id from existing email data
UPDATE notification_preferences SET 
  user_id = (SELECT id FROM users WHERE email = notification_preferences.user_email),
  user_email_new = user_email;

UPDATE work_order_watchers SET 
  user_id = (SELECT id FROM users WHERE email = work_order_watchers.user_email),
  user_email_new = user_email;

UPDATE notifications SET 
  user_id = (SELECT id FROM users WHERE email = notifications.user_email),
  user_email_new = user_email;

UPDATE notification_delivery_logs SET 
  user_id = (SELECT id FROM users WHERE email = notification_delivery_logs.recipient),
  user_email_new = recipient;

-- STEP 4: Drop old columns
ALTER TABLE notification_preferences DROP COLUMN IF EXISTS user_email;
ALTER TABLE notification_preferences RENAME COLUMN user_email_new TO user_email;
ALTER TABLE notification_preferences DROP CONSTRAINT IF EXISTS notification_preferences_pkey;
ALTER TABLE notification_preferences ADD PRIMARY KEY (user_id);

ALTER TABLE work_order_watchers DROP COLUMN IF EXISTS user_email;
ALTER TABLE work_order_watchers RENAME COLUMN user_email_new TO user_email;
ALTER TABLE work_order_watchers DROP CONSTRAINT IF EXISTS ux_work_order_watchers;
ALTER TABLE work_order_watchers ADD CONSTRAINT ux_work_order_watchers UNIQUE (work_order_id, user_id);

ALTER TABLE notifications DROP COLUMN IF EXISTS user_email;
ALTER TABLE notifications RENAME COLUMN user_email_new TO user_email;

ALTER TABLE notification_delivery_logs DROP COLUMN IF EXISTS recipient;
ALTER TABLE notification_delivery_logs RENAME COLUMN user_email_new TO user_email;

-- STEP 5: Verify tables
SELECT 'notification_preferences' as table_name, count(*) as count FROM notification_preferences;
SELECT 'work_order_watchers' as table_name, count(*) as count FROM work_order_watchers;
SELECT 'notifications' as table_name, count(*) as count FROM notifications;
SELECT 'notification_delivery_logs' as table_name, count(*) as count FROM notification_delivery_logs;
