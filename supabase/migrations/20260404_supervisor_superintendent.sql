-- Supervisor & Superintendent Signature Approval Chain Migration
-- Date: 2026-04-04
-- Feature: 016-signature-approval-chain

-- 1. Add approval role columns to users table
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_supervisor BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_superintendent BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS approval_level INTEGER;

-- Add CHECK constraint for approval_level
ALTER TABLE users
  ADD CONSTRAINT approval_level_check 
  CHECK (approval_level IS NULL OR approval_level IN (1, 2, 3));

-- 2. Add signature_status column to work_orders table
ALTER TABLE work_orders
  ADD COLUMN IF NOT EXISTS signature_status TEXT DEFAULT 'unsigned';

-- Add CHECK constraint for signature_status
ALTER TABLE work_orders
  ADD CONSTRAINT signature_status_check 
  CHECK (signature_status IN ('unsigned', 'tech_signed', 'supervisor_approved', 'superintendent_approved', 'completed', 'rejected'));

-- 3. Update work_order_signatures CHECK constraint to include new roles
-- First drop the existing constraint (we need to find its name)
DO $$
DECLARE
  constraint_name TEXT;
BEGIN
  -- Get the current check constraint name
  SELECT conname INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'work_order_signatures'::regclass
    AND contype = 'c'
    AND conname LIKE '%signer_role%';
  
  IF constraint_name IS NOT NULL THEN
    EXECUTE 'ALTER TABLE work_order_signatures DROP CONSTRAINT ' || constraint_name;
  END IF;
END
$$;

-- Add new check constraint allowing new roles
ALTER TABLE work_order_signatures
  ADD CONSTRAINT work_order_signatures_signer_role_check 
  CHECK (signer_role IN ('technician', 'supervisor', 'superintendent', 'admin'));

-- 4. Migrate multi-tech assignments: keep earliest assignment per WO, delete extras
-- Log affected WOs first
INSERT INTO user_activity_log (user_email, user_name, category, action, target_id, detail, created_at)
SELECT
  'system' AS user_email,
  'system' AS user_name,
  'admin' AS category,
  'migration_single_tech' AS action,
  work_order_id::text AS target_id,
  'Kept earliest assignment, deleted extras' AS detail,
  NOW() AS created_at
FROM work_order_assignments
WHERE work_order_id IN (
  SELECT work_order_id FROM work_order_assignments
  GROUP BY work_order_id HAVING COUNT(*) > 1
)
GROUP BY work_order_id;

-- Delete all but the earliest assignment per WO using ctid (no id column exists)
DELETE FROM work_order_assignments a
USING (
  SELECT work_order_id, MIN(assigned_at) AS keep_at
  FROM work_order_assignments
  GROUP BY work_order_id
  HAVING COUNT(*) > 1
) dups
WHERE a.work_order_id = dups.work_order_id
  AND a.assigned_at > dups.keep_at;

-- 5. Add UNIQUE constraint to enforce single technician per WO
ALTER TABLE work_order_assignments
  ADD CONSTRAINT work_order_assignments_work_order_id_unique UNIQUE (work_order_id);
