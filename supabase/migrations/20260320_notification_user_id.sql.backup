-- =============================================================
-- Notification Schema - Create tables + Add user_id FK
-- Run this to create notification tables with user_id support
-- =============================================================

-- STEP 1: Create notification_preferences table
CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  push_enabled boolean NOT NULL DEFAULT true,
  in_app_enabled boolean NOT NULL DEFAULT true,
  mute_all boolean NOT NULL DEFAULT false,
  comment_notifications boolean NOT NULL DEFAULT true,
  status_notifications boolean NOT NULL DEFAULT true,
  system_notifications boolean NOT NULL DEFAULT true,
  admin_all_workorder_comments boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- STEP 2: Create work_order_watchers table
CREATE TABLE IF NOT EXISTS work_order_watchers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id uuid REFERENCES work_orders(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ux_work_order_watchers UNIQUE (work_order_id, user_id)
);

CREATE INDEX IF NOT EXISTS ix_work_order_watchers_work_order_id ON work_order_watchers(work_order_id);
CREATE INDEX IF NOT EXISTS ix_work_order_watchers_user_id ON work_order_watchers(user_id);

-- STEP 3: Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  kind text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_type text NOT NULL,
  source_id text NOT NULL,
  read_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_notifications_user_read_created ON notifications(user_id, read_at, created_at desc);
CREATE INDEX IF NOT EXISTS ix_notifications_source ON notifications(source_type, source_id);
CREATE INDEX IF NOT EXISTS ix_notifications_user_created ON notifications(user_id, created_at desc);

-- STEP 4: Create notification_delivery_logs table
CREATE TABLE IF NOT EXISTS notification_delivery_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid REFERENCES notifications(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  channel text NOT NULL,
  provider text NULL,
  status text NOT NULL,
  provider_message_id text NULL,
  error text NULL,
  attempt integer NOT NULL DEFAULT 1,
  next_retry_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_notification_delivery_status_retry ON notification_delivery_logs(status, next_retry_at);
CREATE INDEX IF NOT EXISTS ix_notification_delivery_notification_id ON notification_delivery_logs(notification_id);
CREATE INDEX IF NOT EXISTS ix_notification_delivery_recipient_created ON notification_delivery_logs(user_id, created_at desc);

-- STEP 5: Create trigger for updated_at
CREATE OR REPLACE FUNCTION set_notification_preferences_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notification_preferences_updated_at ON notification_preferences;
CREATE TRIGGER trg_notification_preferences_updated_at
BEFORE UPDATE ON notification_preferences
FOR EACH ROW EXECUTE FUNCTION set_notification_preferences_updated_at();
