-- Notification system schema
-- Apply in Supabase SQL editor

-- notification_preferences
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  user_email TEXT NOT NULL,
  push_enabled BOOLEAN NOT NULL DEFAULT true,
  in_app_enabled BOOLEAN NOT NULL DEFAULT true,
  mute_all BOOLEAN NOT NULL DEFAULT false,
  comment_notifications BOOLEAN NOT NULL DEFAULT true,
  status_notifications BOOLEAN NOT NULL DEFAULT true,
  system_notifications BOOLEAN NOT NULL DEFAULT true,
  admin_all_workorder_comments BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.set_notification_preferences_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notification_preferences_updated_at ON public.notification_preferences;
CREATE TRIGGER trg_notification_preferences_updated_at
BEFORE UPDATE ON public.notification_preferences
FOR EACH ROW EXECUTE FUNCTION public.set_notification_preferences_updated_at();

-- work_order_watchers
CREATE TABLE IF NOT EXISTS public.work_order_watchers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id UUID REFERENCES public.work_orders(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  user_email TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ux_work_order_watchers UNIQUE (work_order_id, user_id)
);

CREATE INDEX IF NOT EXISTS ix_work_order_watchers_work_order_id
  ON public.work_order_watchers(work_order_id);

CREATE INDEX IF NOT EXISTS ix_work_order_watchers_user_id
  ON public.work_order_watchers(user_id);

-- notifications
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  user_email TEXT NOT NULL,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}'::JSONB,
  source_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  read_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_notifications_user_read_created
  ON public.notifications(user_id, read_at, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_notifications_source
  ON public.notifications(source_type, source_id);

CREATE INDEX IF NOT EXISTS ix_notifications_user_created
  ON public.notifications(user_id, created_at DESC);

-- notification_delivery_logs
CREATE TABLE IF NOT EXISTS public.notification_delivery_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id UUID REFERENCES public.notifications(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  user_email TEXT NOT NULL,
  channel TEXT NOT NULL,
  provider TEXT NULL,
  status TEXT NOT NULL,
  provider_message_id TEXT NULL,
  error TEXT NULL,
  attempt INTEGER NOT NULL DEFAULT 1,
  next_retry_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_notification_delivery_status_retry
  ON public.notification_delivery_logs(status, next_retry_at);

CREATE INDEX IF NOT EXISTS ix_notification_delivery_notification_id
  ON public.notification_delivery_logs(notification_id);

CREATE INDEX IF NOT EXISTS ix_notification_delivery_recipient_created
  ON public.notification_delivery_logs(user_id, created_at DESC);
