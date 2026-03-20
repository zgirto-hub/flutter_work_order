-- ============================================
-- WORK ORDER SYSTEM - DATABASE V2 MIGRATION
-- Run in Supabase SQL Editor
-- ============================================

-- STEP 1: DROP EXISTING TABLES (in correct dependency order)

DROP TABLE IF EXISTS work_order_attachments CASCADE;
DROP TABLE IF EXISTS work_order_comments CASCADE;
DROP TABLE IF EXISTS work_order_status_logs CASCADE;
DROP TABLE IF EXISTS work_order_assignments CASCADE;
DROP TABLE IF EXISTS work_order_watchers CASCADE;
DROP TABLE IF EXISTS notification_delivery_logs CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS work_orders CASCADE;
DROP TABLE IF EXISTS fixer_departments CASCADE;
DROP TABLE IF EXISTS fixer_reporters CASCADE;
DROP TABLE IF EXISTS it_department_reporters CASCADE;
DROP TABLE IF EXISTS it_teams CASCADE;
DROP TABLE IF EXISTS departments CASCADE;
DROP TABLE IF EXISTS employees CASCADE;
DROP TABLE IF EXISTS user_profiles CASCADE;
DROP TABLE IF EXISTS notification_preferences CASCADE;

-- Note: Keep auth.users table (Supabase built-in) - DO NOT DROP

-- STEP 2: CREATE NEW TABLES

-- 1. users (core user table - different from auth.users)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_id UUID UNIQUE,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    mobile TEXT,
    location TEXT,
    user_type TEXT NOT NULL CHECK (user_type IN ('admin', 'fixer', 'reporter')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. fixer_departments (normalized fixer-department mapping)
CREATE TABLE IF NOT EXISTS fixer_departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fixer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    department TEXT NOT NULL,
    UNIQUE (fixer_id, department)
);

-- 3. work_orders (simplified core table)
CREATE TABLE IF NOT EXISTS work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_no TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    location TEXT,
    mobile_number TEXT,
    department TEXT NOT NULL,
    type TEXT DEFAULT 'Technical',
    status TEXT NOT NULL DEFAULT 'Pending'
        CHECK (status IN ('Pending', 'In Progress', 'Resolved', 'Closed')),
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    closed_by UUID REFERENCES users(id),
    closed_at TIMESTAMPTZ,
    tech_notes TEXT
);

-- 4. work_order_assignments
CREATE TABLE IF NOT EXISTS work_order_assignments (
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    fixer_id UUID REFERENCES users(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT now(),
    assigned_by UUID REFERENCES users(id),
    PRIMARY KEY (work_order_id, fixer_id)
);

-- 5. work_order_status_logs (audit trail - append only)
CREATE TABLE IF NOT EXISTS work_order_status_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    changed_by UUID REFERENCES users(id),
    old_status TEXT,
    new_status TEXT,
    note TEXT,
    changed_at TIMESTAMPTZ DEFAULT now()
);

-- 6. notifications (in-app inbox)
CREATE TABLE IF NOT EXISTS notifications (
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

-- 7. notification_preferences (per-user settings)
CREATE TABLE IF NOT EXISTS notification_preferences (
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

-- 8. notification_delivery_logs (push delivery audit)
CREATE TABLE IF NOT EXISTS notification_delivery_logs (
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

-- 9. work_order_watchers (extra followers)
CREATE TABLE IF NOT EXISTS work_order_watchers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    user_email TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(work_order_id, user_email)
);

-- 10. work_order_comments
CREATE TABLE IF NOT EXISTS work_order_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    author_email TEXT NOT NULL,
    author_name TEXT,
    body TEXT NOT NULL,
    type TEXT DEFAULT 'comment',
    meta JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 11. work_order_attachments
CREATE TABLE IF NOT EXISTS work_order_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_url TEXT NOT NULL,
    file_type TEXT,
    uploaded_by TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- STEP 3: CREATE INDEXES

CREATE INDEX IF NOT EXISTS idx_work_orders_department ON work_orders(department);
CREATE INDEX IF NOT EXISTS idx_work_orders_created_by ON work_orders(created_by);
CREATE INDEX IF NOT EXISTS idx_work_orders_status ON work_orders(status);
CREATE INDEX IF NOT EXISTS idx_work_orders_created_at ON work_orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_auth_id ON users(auth_id);
CREATE INDEX IF NOT EXISTS idx_users_user_type ON users(user_type);
CREATE INDEX IF NOT EXISTS idx_work_order_assignments_wo ON work_order_assignments(work_order_id);
CREATE INDEX IF NOT EXISTS idx_work_order_assignments_fixer ON work_order_assignments(fixer_id);
CREATE INDEX IF NOT EXISTS idx_work_order_comments_wo ON work_order_comments(work_order_id);
CREATE INDEX IF NOT EXISTS idx_work_order_status_logs_wo ON work_order_status_logs(work_order_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON notifications(user_email, read_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fixers_departments_fixer ON fixer_departments(fixer_id);
CREATE INDEX IF NOT EXISTS idx_fixers_departments_dept ON fixer_departments(department);

-- ============================================
-- MIGRATION COMPLETE
-- ============================================
