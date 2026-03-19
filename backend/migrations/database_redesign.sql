-- ================================================
-- DATABASE REDESIGN - DROP ALL OLD TABLES
-- ================================================

-- Drop tables in correct order (dependencies first)
DROP TABLE IF EXISTS work_order_watchers CASCADE;
DROP TABLE IF EXISTS work_order_assignments CASCADE;
DROP TABLE IF EXISTS work_order_attachments CASCADE;
DROP TABLE IF EXISTS work_order_comments CASCADE;
DROP TABLE IF EXISTS notification_delivery_logs CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS notification_preferences CASCADE;
DROP TABLE IF EXISTS work_orders CASCADE;
DROP TABLE IF EXISTS it_department_reporters CASCADE;
DROP TABLE IF EXISTS it_teams CASCADE;
DROP TABLE IF EXISTS departments CASCADE;
DROP TABLE IF EXISTS employees CASCADE;
DROP TABLE IF EXISTS user_profiles CASCADE;

-- ================================================
-- CREATE NEW TABLES
-- ================================================

-- 1. USERS (Single table for all users)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_id UUID UNIQUE,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    mobile TEXT,
    location TEXT,
    user_type TEXT NOT NULL CHECK (user_type IN ('admin', 'fixer', 'reporter')),
    department TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. FIXER_REPORTERS
CREATE TABLE fixer_reporters (
    fixer_department TEXT PRIMARY KEY,
    reporter_departments TEXT[] NOT NULL
);

-- 3. WORK_ORDERS
CREATE TABLE work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_no TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    location TEXT,
    mobile_number TEXT,
    department TEXT NOT NULL,
    type TEXT DEFAULT 'Technical',
    status TEXT DEFAULT 'Pending',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. WORK_ORDER_ASSIGNMENTS
CREATE TABLE work_order_assignments (
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (work_order_id, user_id)
);

-- ================================================
-- RECREATE NOTIFICATION TABLES
-- ================================================

-- Per-user notification settings
CREATE TABLE notification_preferences (
    user_email TEXT PRIMARY KEY,
    push_enabled BOOLEAN DEFAULT true,
    in_app_enabled BOOLEAN DEFAULT true,
    mute_all BOOLEAN DEFAULT false,
    comment_notifications BOOLEAN DEFAULT true,
    status_notifications BOOLEAN DEFAULT true,
    system_notifications BOOLEAN DEFAULT true,
    admin_all_workorder_comments BOOLEAN DEFAULT false,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Extra followers beyond assignees/requester/creator
CREATE TABLE work_order_watchers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    user_email TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(work_order_id, user_email)
);

-- In-app inbox (one row per recipient per event)
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_email TEXT NOT NULL,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB DEFAULT '{}',
    source_type TEXT NOT NULL,
    source_id TEXT NOT NULL,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_notifications_user_read ON notifications(user_email, read_at, created_at DESC);
CREATE INDEX idx_notifications_source ON notifications(source_type, source_id);

-- Push delivery audit trail
CREATE TABLE notification_delivery_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID REFERENCES notifications(id) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    provider TEXT,
    recipient TEXT NOT NULL,
    status TEXT NOT NULL,
    provider_message_id TEXT,
    error TEXT,
    attempt INTEGER DEFAULT 1,
    next_retry_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_delivery_logs_status_retry ON notification_delivery_logs(status, next_retry_at);
CREATE INDEX idx_delivery_logs_notification ON notification_delivery_logs(notification_id);

-- Work order comments
CREATE TABLE work_order_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    author_email TEXT NOT NULL,
    author_name TEXT,
    body TEXT NOT NULL,
    type TEXT DEFAULT 'comment',
    meta JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_comments_work_order ON work_order_comments(work_order_id, created_at);

-- Work order attachments
CREATE TABLE work_order_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_url TEXT NOT NULL,
    file_type TEXT,
    uploaded_by TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_attachments_work_order ON work_order_attachments(work_order_id);

-- ================================================
-- SEED FIXER_REPORTERS
-- ================================================

INSERT INTO fixer_reporters (fixer_department, reporter_departments) VALUES
  ('AFTN', ARRAY['Operations', 'ATC', 'Finance', 'NOTAM', 'General', 'MET']),
  ('Network', ARRAY['IT-Support', 'Helpdesk']),
  ('Security', ARRAY['General', 'Operations', 'ATC', 'Finance', 'NOTAM', 'MET', 'IT-Support', 'Helpdesk']);
