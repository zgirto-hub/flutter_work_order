-- ============================================
-- Align DB schema with code (fixer → technician)
-- Handles any starting state safely
-- Run in Supabase SQL Editor
-- ============================================

-- ============================================
-- STEP 1: Ensure departments table has is_active column
-- ============================================
ALTER TABLE departments ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- ============================================
-- STEP 2: Ensure work_orders uses department_id UUID (not department TEXT)
-- ============================================
-- Check if work_orders has 'department' TEXT column instead of 'department_id' UUID
DO $$
BEGIN
    -- If department_id column doesn't exist, we need to migrate from TEXT department
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'work_orders' AND column_name = 'department_id'
    ) THEN
        -- Add department_id column
        ALTER TABLE work_orders ADD COLUMN department_id UUID REFERENCES departments(id);

        -- Populate from TEXT department column if it exists
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'work_orders' AND column_name = 'department'
        ) THEN
            UPDATE work_orders wo
            SET department_id = d.id
            FROM departments d
            WHERE wo.department = d.name;

            -- Make NOT NULL after populating
            -- (only if all rows have a match — otherwise leave nullable)
            IF NOT EXISTS (SELECT 1 FROM work_orders WHERE department_id IS NULL) THEN
                ALTER TABLE work_orders ALTER COLUMN department_id SET NOT NULL;
            END IF;

            ALTER TABLE work_orders DROP COLUMN department;
        END IF;
    END IF;
END $$;

-- ============================================
-- STEP 3: Ensure technician_departments table exists
-- ============================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'fixer_departments'
    ) THEN
        -- Rename existing fixer_departments
        ALTER TABLE fixer_departments RENAME TO technician_departments;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'technician_departments'
    ) THEN
        -- Create from scratch
        CREATE TABLE technician_departments (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            technician_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            department_id UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
            UNIQUE (technician_id, department_id)
        );
    END IF;
END $$;

-- Rename columns in technician_departments if needed
DO $$
BEGIN
    -- Rename fixer_id → technician_id
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'technician_departments' AND column_name = 'fixer_id'
    ) THEN
        ALTER TABLE technician_departments RENAME COLUMN fixer_id TO technician_id;
    END IF;

    -- If it has 'department' TEXT instead of 'department_id' UUID, migrate
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'technician_departments' AND column_name = 'department'
        AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'technician_departments' AND column_name = 'department_id'
    ) THEN
        ALTER TABLE technician_departments ADD COLUMN department_id UUID REFERENCES departments(id) ON DELETE CASCADE;

        UPDATE technician_departments td
        SET department_id = d.id
        FROM departments d
        WHERE td.department = d.name;

        -- Drop rows that didn't match
        DELETE FROM technician_departments WHERE department_id IS NULL;
        ALTER TABLE technician_departments ALTER COLUMN department_id SET NOT NULL;
        ALTER TABLE technician_departments DROP COLUMN department;
    END IF;
END $$;

-- ============================================
-- STEP 4: Ensure work_order_assignments uses technician_id
-- ============================================
DO $$
BEGIN
    -- Rename fixer_id → technician_id
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'work_order_assignments' AND column_name = 'fixer_id'
    ) THEN
        ALTER TABLE work_order_assignments RENAME COLUMN fixer_id TO technician_id;
    END IF;

    -- Rename user_id → technician_id (from database_redesign.sql schema)
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'work_order_assignments' AND column_name = 'user_id'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'work_order_assignments' AND column_name = 'technician_id'
    ) THEN
        ALTER TABLE work_order_assignments RENAME COLUMN user_id TO technician_id;
    END IF;

    -- Add assigned_at if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'work_order_assignments' AND column_name = 'assigned_at'
    ) THEN
        ALTER TABLE work_order_assignments ADD COLUMN assigned_at TIMESTAMPTZ DEFAULT now();
    END IF;

    -- Add assigned_by if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'work_order_assignments' AND column_name = 'assigned_by'
    ) THEN
        ALTER TABLE work_order_assignments ADD COLUMN assigned_by UUID REFERENCES users(id);
    END IF;
END $$;

-- ============================================
-- STEP 5: Update user_type constraint
-- ============================================
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_type_check;
ALTER TABLE users ADD CONSTRAINT users_user_type_check
    CHECK (user_type IN ('admin', 'technician', 'reporter'));

UPDATE users SET user_type = 'technician' WHERE user_type = 'fixer';

-- ============================================
-- STEP 6: Ensure work_order_status_logs exists
-- ============================================
CREATE TABLE IF NOT EXISTS work_order_status_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    changed_by UUID REFERENCES users(id),
    old_status TEXT,
    new_status TEXT,
    note TEXT,
    changed_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- STEP 7: Clean up old indexes, create new ones
-- ============================================
DROP INDEX IF EXISTS idx_fixer_departments_fixer_id;
DROP INDEX IF EXISTS idx_fixer_departments_department_id;
DROP INDEX IF EXISTS idx_fixers_departments_fixer;
DROP INDEX IF EXISTS idx_fixers_departments_dept;
DROP INDEX IF EXISTS idx_work_order_assignments_fixer;
DROP INDEX IF EXISTS idx_work_orders_department;

CREATE INDEX IF NOT EXISTS idx_work_orders_department_id ON work_orders(department_id);
CREATE INDEX IF NOT EXISTS idx_technician_departments_technician_id ON technician_departments(technician_id);
CREATE INDEX IF NOT EXISTS idx_technician_departments_department_id ON technician_departments(department_id);
CREATE INDEX IF NOT EXISTS idx_work_order_assignments_technician ON work_order_assignments(technician_id);
CREATE INDEX IF NOT EXISTS idx_work_order_assignments_wo ON work_order_assignments(work_order_id);
