-- =============================================================
-- Work Order System — Full Database Migration
-- Run in this exact order in Supabase SQL Editor
-- =============================================================

-- =============================================================
-- STEP 1 — Drop old tables (with CASCADE to remove dependencies)
-- =============================================================
DROP TABLE IF EXISTS notification_delivery_logs CASCADE;
DROP TABLE IF EXISTS work_order_comments CASCADE;
DROP TABLE IF EXISTS work_order_watchers CASCADE;
DROP TABLE IF EXISTS work_order_attachments CASCADE;
DROP TABLE IF EXISTS work_order_assignments CASCADE;
DROP TABLE IF EXISTS work_order_status_logs CASCADE;
DROP TABLE IF EXISTS work_orders CASCADE;
DROP TABLE IF EXISTS technician_departments CASCADE;
DROP TABLE IF EXISTS it_department_reporters CASCADE;
DROP TABLE IF EXISTS it_teams CASCADE;
DROP TABLE IF EXISTS departments CASCADE;
DROP TABLE IF EXISTS employees CASCADE;
DROP TABLE IF EXISTS user_profiles CASCADE;
DROP TABLE IF EXISTS technician_reporters CASCADE;
DROP TABLE IF EXISTS notification_preferences CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;

-- =============================================================
-- STEP 2 — Create tables (parent before child)
-- =============================================================

CREATE TABLE departments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT UNIQUE NOT NULL,
    is_active  BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_id     UUID UNIQUE,
    email       TEXT UNIQUE NOT NULL,
    full_name   TEXT,
    mobile      TEXT,
    location    TEXT,
    user_type   TEXT NOT NULL CHECK (user_type IN ('admin', 'technician', 'reporter')),
    is_active   BOOLEAN DEFAULT true,
    created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE technician_departments (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    technician_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    department_id UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
    UNIQUE (technician_id, department_id)
);

CREATE TABLE work_orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_no          TEXT UNIQUE NOT NULL,
    title           TEXT NOT NULL,
    description     TEXT,
    location        TEXT,
    mobile_number   TEXT,
    department_id   UUID NOT NULL REFERENCES departments(id),
    type            TEXT DEFAULT 'Technical',
    status          TEXT NOT NULL DEFAULT 'Pending'
                        CHECK (status IN ('Pending', 'In Progress', 'Resolved', 'Closed')),
    tech_notes      TEXT,
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now(),
    closed_by       UUID REFERENCES users(id),
    closed_at       TIMESTAMPTZ
);

CREATE TABLE work_order_assignments (
    work_order_id   UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    technician_id   UUID REFERENCES users(id) ON DELETE CASCADE,
    assigned_at     TIMESTAMPTZ DEFAULT now(),
    assigned_by     UUID REFERENCES users(id),
    PRIMARY KEY (work_order_id, technician_id)
);

CREATE TABLE work_order_status_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id   UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    changed_by      UUID REFERENCES users(id),
    old_status      TEXT,
    new_status      TEXT,
    note            TEXT,
    changed_at      TIMESTAMPTZ DEFAULT now()
);

-- =============================================================
-- STEP 3 — Seed departments (MUST be before FK population)
-- =============================================================
INSERT INTO departments (name) VALUES
    ('Operations'),
    ('ATC'),
    ('Finance'),
    ('NOTAM'),
    ('General'),
    ('MET'),
    ('IT-Support'),
    ('Helpdesk'),
    ('AFTN'),
    ('ATM')
ON CONFLICT (name) DO NOTHING;

-- =============================================================
-- STEP 4 — Create indexes
-- =============================================================
CREATE INDEX IF NOT EXISTS idx_work_orders_department_id
    ON work_orders(department_id);

CREATE INDEX IF NOT EXISTS idx_technician_departments_department_id
    ON technician_departments(department_id);

CREATE INDEX IF NOT EXISTS idx_technician_departments_technician_id
    ON technician_departments(technician_id);

-- =============================================================
-- STEP 5 — RLS Policies (optional for development)
-- =============================================================
-- Uncomment if using RLS in production

-- DROP POLICY IF EXISTS "reporter_own_wos" ON work_orders;
-- CREATE POLICY "reporter_own_wos" ON work_orders
-- FOR SELECT USING (
--     (SELECT user_type FROM users WHERE auth_id = auth.uid()) = 'reporter'
--     AND created_by = (SELECT id FROM users WHERE auth_id = auth.uid())
-- );

-- DROP POLICY IF EXISTS "technician_department_wos" ON work_orders;
-- CREATE POLICY "technician_department_wos" ON work_orders
-- FOR SELECT USING (
--     (SELECT user_type FROM users WHERE auth_id = auth.uid()) = 'technician'
--     AND department_id IN (
--         SELECT department_id FROM technician_departments
--         WHERE technician_id = (SELECT id FROM users WHERE auth_id = auth.uid())
--     )
-- );

-- DROP POLICY IF EXISTS "admin_all_wos" ON work_orders;
-- CREATE POLICY "admin_all_wos" ON work_orders
-- FOR SELECT USING (
--     (SELECT user_type FROM users WHERE auth_id = auth.uid()) = 'admin'
-- );

-- CREATE POLICY "admin_manage_departments" ON departments
-- FOR ALL USING (
--     (SELECT user_type FROM users WHERE auth_id = auth.uid()) = 'admin'
-- );
