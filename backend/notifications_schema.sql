-- Notification system foundation
-- Apply in Supabase SQL editor.

create table if not exists public.notification_preferences (
  user_email text primary key,
  push_enabled boolean not null default true,
  in_app_enabled boolean not null default true,
  mute_all boolean not null default false,
  comment_notifications boolean not null default true,
  status_notifications boolean not null default true,
  system_notifications boolean not null default true,
  updated_at timestamptz not null default now()
);

create or replace function public.set_notification_preferences_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_notification_preferences_updated_at on public.notification_preferences;
create trigger trg_notification_preferences_updated_at
before update on public.notification_preferences
for each row execute function public.set_notification_preferences_updated_at();

create table if not exists public.work_order_watchers (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  user_email text not null,
  created_at timestamptz not null default now(),
  constraint ux_work_order_watchers unique (work_order_id, user_email)
);

create index if not exists ix_work_order_watchers_work_order_id
  on public.work_order_watchers(work_order_id);

create index if not exists ix_work_order_watchers_user_email
  on public.work_order_watchers(user_email);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_email text not null,
  kind text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  source_type text not null,
  source_id text not null,
  read_at timestamptz null,
  created_at timestamptz not null default now()
);

create index if not exists ix_notifications_user_read_created
  on public.notifications(user_email, read_at, created_at desc);

create index if not exists ix_notifications_source
  on public.notifications(source_type, source_id);

create index if not exists ix_notifications_user_created
  on public.notifications(user_email, created_at desc);

create table if not exists public.notification_delivery_logs (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid null references public.notifications(id) on delete cascade,
  channel text not null,
  provider text null,
  recipient text not null,
  status text not null,
  provider_message_id text null,
  error text null,
  attempt integer not null default 1,
  next_retry_at timestamptz null,
  created_at timestamptz not null default now()
);

create index if not exists ix_notification_delivery_status_retry
  on public.notification_delivery_logs(status, next_retry_at);

create index if not exists ix_notification_delivery_notification_id
  on public.notification_delivery_logs(notification_id);

create index if not exists ix_notification_delivery_recipient_created
  on public.notification_delivery_logs(recipient, created_at desc);
