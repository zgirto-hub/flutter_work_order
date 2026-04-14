-- Migration: Create systems table and migrate FK references
-- Created: 20260414124125

-- Step 1: Create systems table
CREATE TABLE IF NOT EXISTS systems (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    category text DEFAULT NULL,
    sort_order integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    needs_review boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_systems_name_lower ON systems(LOWER(name));
CREATE INDEX idx_systems_active ON systems(is_active) WHERE is_active = true;
CREATE INDEX idx_systems_sort ON systems(sort_order);

-- Step 2: Seed 24 canonical systems
INSERT INTO systems (name, category, sort_order, is_active, needs_review) VALUES
('AIDA-NG', NULL, 1, true, false),
('CADAS-ATS', NULL, 2, true, false),
('CADAS-IMS', NULL, 3, true, false),
('Billing System', NULL, 4, true, false),
('UPS', NULL, 5, true, false),
('Permissions', NULL, 6, true, false),
('IRTOS', NULL, 7, true, false),
('International Circuits - Beirut', 'International Circuits', 8, true, false),
('International Circuits - Damascus', 'International Circuits', 9, true, false),
('International Circuits - Karachi', 'International Circuits', 10, true, false),
('International Circuits - Tehran', 'International Circuits', 11, true, false),
('International Circuits - Baghdad', 'International Circuits', 12, true, false),
('International Circuits - Bahrain', 'International Circuits', 13, true, false),
('INDRA CCTV - Camera 1', 'INDRA CCTV', 14, true, false),
('INDRA CCTV - Camera 2', 'INDRA CCTV', 15, true, false),
('INDRA CCTV - Camera 3', 'INDRA CCTV', 16, true, false),
('INDRA CCTV - Camera 4', 'INDRA CCTV', 17, true, false),
('INDRA CCTV - Camera 5', 'INDRA CCTV', 18, true, false),
('INDRA CCTV - Camera 6', 'INDRA CCTV', 19, true, false),
('INDRA CCTV - Camera 7', 'INDRA CCTV', 20, true, false),
('INDRA CCTV - Camera 8', 'INDRA CCTV', 21, true, false),
('INDRA CCTV - Camera 9', 'INDRA CCTV', 22, true, false),
('INDRA CCTV - Camera 10', 'INDRA CCTV', 23, true, false)
ON CONFLICT DO NOTHING;

-- Step 3: Migrate asset_system_links
-- Add system_id column
ALTER TABLE asset_system_links ADD COLUMN IF NOT EXISTS system_id uuid;

-- Update system_id from matching systems
UPDATE asset_system_links ASL
SET system_id = S.id
FROM systems S
WHERE LOWER(ASL.system) = LOWER(S.name);

-- Handle unmatched values - insert into systems with needs_review=true
-- First get max sort_order
DO $$
DECLARE
    max_sort int;
BEGIN
    SELECT COALESCE(MAX(sort_order), 0) INTO max_sort FROM systems;
    
    -- Insert unmatched system names (preserve original casing for admin review)
    INSERT INTO systems (name, category, sort_order, is_active, needs_review)
    SELECT DISTINCT ON (LOWER(ASL.system)) ASL.system, NULL, max_sort + ROW_NUMBER() OVER (ORDER BY ASL.system), true, true
    FROM asset_system_links ASL
    WHERE ASL.system_id IS NULL AND ASL.system IS NOT NULL
    ON CONFLICT DO NOTHING;
    
    -- Update system_id for newly inserted systems
    UPDATE asset_system_links ASL
    SET system_id = S.id
    FROM systems S
    WHERE LOWER(ASL.system) = LOWER(S.name) AND ASL.system_id IS NULL;
END $$;

-- Add foreign key constraint
ALTER TABLE asset_system_links 
    ADD CONSTRAINT fk_asset_system_links_system 
    FOREIGN KEY (system_id) REFERENCES systems(id);

-- Set NOT NULL
ALTER TABLE asset_system_links ALTER COLUMN system_id SET NOT NULL;

-- Drop old indexes
DROP INDEX IF EXISTS idx_asset_system_links_unique;
DROP INDEX IF EXISTS idx_asset_system_links_primary_standby;

-- Create new indexes
CREATE UNIQUE INDEX idx_asset_system_links_unique 
    ON asset_system_links(asset_id, system_id, role);
CREATE UNIQUE INDEX idx_asset_system_links_primary_standby 
    ON asset_system_links(system_id, role) WHERE role IN ('primary', 'standby');

-- Drop old system column
ALTER TABLE asset_system_links DROP COLUMN IF EXISTS system;

-- Step 4: Migrate system_status_reports
-- Add system_id column
ALTER TABLE system_status_reports ADD COLUMN IF NOT EXISTS system_id uuid;

-- Update system_id from matching systems
UPDATE system_status_reports SSR
SET system_id = S.id
FROM systems S
WHERE LOWER(SSR.system_name) = LOWER(S.name);

-- Handle unmatched values - insert into systems with needs_review=true
DO $$
DECLARE
    max_sort int;
BEGIN
    SELECT COALESCE(MAX(sort_order), 0) INTO max_sort FROM systems;
    
    INSERT INTO systems (name, category, sort_order, is_active, needs_review)
    SELECT DISTINCT ON (LOWER(SSR.system_name)) SSR.system_name, NULL, max_sort + ROW_NUMBER() OVER (ORDER BY SSR.system_name), true, true
    FROM system_status_reports SSR
    WHERE SSR.system_id IS NULL AND SSR.system_name IS NOT NULL
    ON CONFLICT DO NOTHING;
    
    UPDATE system_status_reports SSR
    SET system_id = S.id
    FROM systems S
    WHERE LOWER(SSR.system_name) = LOWER(S.name) AND SSR.system_id IS NULL;
END $$;

-- Add foreign key constraint
ALTER TABLE system_status_reports 
    ADD CONSTRAINT fk_system_status_reports_system 
    FOREIGN KEY (system_id) REFERENCES systems(id);

-- Set NOT NULL
ALTER TABLE system_status_reports ALTER COLUMN system_id SET NOT NULL;

-- Drop old system_name column
ALTER TABLE system_status_reports DROP COLUMN IF EXISTS system_name;