-- ============================================
-- PHASE 1: Database Schema Changes
-- Run this in Supabase SQL Editor
-- ============================================

-- 1. Add columns to employees table
ALTER TABLE employees ADD COLUMN IF NOT EXISTS department TEXT NOT NULL DEFAULT 'General';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS mobile TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS location TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS user_type TEXT DEFAULT 'tech';

-- 2. Add columns to work_orders table
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS department TEXT NOT NULL DEFAULT 'General';
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS mobile_number TEXT;

-- 3. Remove request_id column (safe - only if no production data)
ALTER TABLE work_orders DROP COLUMN IF EXISTS request_id;

-- 4. Update existing employees with defaults
UPDATE employees SET department = 'General' WHERE department IS NULL OR department = '';
UPDATE employees SET user_type = 'tech' WHERE user_type IS NULL OR user_type = '';

-- 5. Create work_order_attachments table
CREATE TABLE IF NOT EXISTS work_order_attachments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id uuid NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    file_name text NOT NULL,
    file_url text NOT NULL,
    file_type text,
    created_at timestamptz DEFAULT now()
);

-- 6. Drop requests tables (ONLY AFTER confirming no production data)
-- Uncomment when ready:
-- DROP TABLE IF EXISTS request_attachments;
-- DROP TABLE IF EXISTS requests;
-- DROP INDEX IF EXISTS ux_work_orders_request_id;
