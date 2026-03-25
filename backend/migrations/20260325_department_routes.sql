-- =============================================================
-- Migration: Department Routing Rules
-- Adds department_routes table for controlling which departments
-- can send work orders to which other departments.
-- Also drops the technician_departments table (technicians now
-- use user.department_id instead).
-- =============================================================

-- 1. Create department_routes table
CREATE TABLE IF NOT EXISTS department_routes (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_department_id  UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
    target_department_id  UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
    created_at            TIMESTAMPTZ DEFAULT now(),
    UNIQUE (source_department_id, target_department_id),
    CHECK (source_department_id != target_department_id)
);

CREATE INDEX IF NOT EXISTS idx_department_routes_source
    ON department_routes(source_department_id);

CREATE INDEX IF NOT EXISTS idx_department_routes_target
    ON department_routes(target_department_id);

-- 2. Ensure users table has department_id column
ALTER TABLE users ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id);

-- 3. Drop the technician_departments table (no longer needed)
DROP TABLE IF EXISTS technician_departments CASCADE;
