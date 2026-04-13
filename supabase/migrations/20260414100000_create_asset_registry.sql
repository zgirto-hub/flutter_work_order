-- Asset Registry: assets and asset_system_links tables
-- Created: 2026-04-14

-- Add system column to existing tables (moved here because original migrations already applied)
ALTER TABLE work_order_entities ADD COLUMN IF NOT EXISTS system text;
ALTER TABLE pattern_alerts ADD COLUMN IF NOT EXISTS system text;

-- assets: physical devices at DGCA
CREATE TABLE IF NOT EXISTS assets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE,
    type text NOT NULL CHECK (type IN ('workstation', 'server', 'camera', 'router', 'switch', 'media_converter', 'power_adapter')),
    location text NOT NULL,
    notes text DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- asset_system_links: many-to-many relationship between assets and systems
CREATE TABLE IF NOT EXISTS asset_system_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id uuid NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    system text NOT NULL,
    role text NOT NULL CHECK (role IN ('primary', 'standby', 'client')),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_assets_name_unique ON assets(name);
CREATE INDEX IF NOT EXISTS idx_assets_type ON assets(type);
CREATE UNIQUE INDEX IF NOT EXISTS idx_asset_system_links_unique ON asset_system_links(asset_id, system, role);
CREATE UNIQUE INDEX IF NOT EXISTS idx_asset_system_links_primary_standby ON asset_system_links(system, role) WHERE role IN ('primary', 'standby');
CREATE INDEX IF NOT EXISTS idx_asset_system_links_asset_id ON asset_system_links(asset_id);

-- Comments
COMMENT ON TABLE assets IS 'Physical devices at DGCA (workstations, servers, cameras, routers, etc.)';
COMMENT ON TABLE asset_system_links IS 'System associations for assets with roles (primary, standby, client)';

-- Add asset_context column to pattern_alerts table (for alert enrichment)
ALTER TABLE pattern_alerts ADD COLUMN IF NOT EXISTS asset_context jsonb DEFAULT NULL;

-- Seed data: AIDA-NG international circuit assets
INSERT INTO assets (name, type, location, notes) VALUES
    ('Bahrain', 'router', 'International Circuit', 'International circuit connection'),
    ('Karachi', 'router', 'International Circuit', 'International circuit connection'),
    ('Tehran', 'router', 'International Circuit', 'International circuit connection'),
    ('Doha', 'router', 'International Circuit', 'International circuit connection'),
    ('Damascus', 'router', 'International Circuit', 'International circuit connection'),
    ('Beirut', 'router', 'International Circuit', 'International circuit connection')
ON CONFLICT (name) DO NOTHING;

-- Seed system links for AIDA-NG circuits (all as 'client' role)
INSERT INTO asset_system_links (asset_id, system, role)
SELECT a.id, 'AIDA-NG', 'client'
FROM assets a
WHERE a.name IN ('Bahrain', 'Karachi', 'Tehran', 'Doha', 'Damascus', 'Beirut')
AND NOT EXISTS (
    SELECT 1 FROM asset_system_links l 
    WHERE l.asset_id = a.id AND l.system = 'AIDA-NG' AND l.role = 'client'
);