-- =============================================================
-- Rename 'fixer' to 'technician' across the schema
-- =============================================================

-- 1. Update existing user_type data
UPDATE users SET user_type = 'technician' WHERE user_type = 'fixer';

-- 2. Update CHECK constraint on users.user_type
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_type_check;
ALTER TABLE users ADD CONSTRAINT users_user_type_check
    CHECK (user_type IN ('admin', 'technician', 'reporter'));

-- 3. Rename fixer_departments table to technician_departments
ALTER TABLE fixer_departments RENAME TO technician_departments;

-- 4. Rename fixer_id columns
ALTER TABLE technician_departments RENAME COLUMN fixer_id TO technician_id;
ALTER TABLE work_order_assignments RENAME COLUMN fixer_id TO technician_id;

-- 5. Rename indexes
DROP INDEX IF EXISTS idx_fixer_departments_department_id;
DROP INDEX IF EXISTS idx_fixer_departments_fixer_id;
CREATE INDEX IF NOT EXISTS idx_technician_departments_department_id
    ON technician_departments(department_id);
CREATE INDEX IF NOT EXISTS idx_technician_departments_technician_id
    ON technician_departments(technician_id);
