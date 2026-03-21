-- ============================================
-- Rename fixer → technician in database schema
-- Aligns DB with code refactor (fixer → technician)
-- Run in Supabase SQL Editor
-- ============================================

-- STEP 1: Rename fixer_departments table → technician_departments
ALTER TABLE IF EXISTS fixer_departments RENAME TO technician_departments;

-- STEP 2: Rename fixer_id → technician_id in technician_departments
ALTER TABLE technician_departments RENAME COLUMN fixer_id TO technician_id;

-- STEP 3: Rename fixer_id → technician_id in work_order_assignments
ALTER TABLE work_order_assignments RENAME COLUMN fixer_id TO technician_id;

-- STEP 4: Update user_type CHECK constraint (fixer → technician)
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_type_check;
ALTER TABLE users ADD CONSTRAINT users_user_type_check
    CHECK (user_type IN ('admin', 'technician', 'reporter'));

-- Update existing 'fixer' values to 'technician'
UPDATE users SET user_type = 'technician' WHERE user_type = 'fixer';

-- STEP 5: Rename indexes to match new names
DROP INDEX IF EXISTS idx_fixer_departments_fixer_id;
DROP INDEX IF EXISTS idx_fixer_departments_department_id;
DROP INDEX IF EXISTS idx_fixers_departments_fixer;
DROP INDEX IF EXISTS idx_fixers_departments_dept;
DROP INDEX IF EXISTS idx_work_order_assignments_fixer;

CREATE INDEX IF NOT EXISTS idx_technician_departments_technician_id
    ON technician_departments(technician_id);
CREATE INDEX IF NOT EXISTS idx_technician_departments_department_id
    ON technician_departments(department_id);
CREATE INDEX IF NOT EXISTS idx_work_order_assignments_technician
    ON work_order_assignments(technician_id);
