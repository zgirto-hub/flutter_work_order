BEGIN;

-- Add has_contingency column to systems table
ALTER TABLE systems
ADD COLUMN IF NOT EXISTS has_contingency boolean NOT NULL DEFAULT false;

-- Add site column to asset_system_links table
ALTER TABLE asset_system_links
ADD COLUMN IF NOT EXISTS site text;

UPDATE asset_system_links
SET site = 'production'
WHERE site IS NULL;

ALTER TABLE asset_system_links
ALTER COLUMN site SET DEFAULT 'production';

ALTER TABLE asset_system_links
ALTER COLUMN site SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'asset_system_links_site_check'
    ) THEN
        ALTER TABLE asset_system_links
        ADD CONSTRAINT asset_system_links_site_check
        CHECK (site IN ('production', 'contingency'));
    END IF;
END $$;

DROP INDEX IF EXISTS idx_asset_system_links_unique;
DROP INDEX IF EXISTS idx_asset_system_links_primary_standby;

DO $$
DECLARE
    indra_system_id uuid;
    aida_system_id uuid;
    camera_system record;
    camera_link record;
    circuit_link record;
    camera_asset_id uuid;
    camera_asset_name text;
    next_role text;
BEGIN
    SELECT id INTO indra_system_id
    FROM systems
    WHERE LOWER(name) = 'indra cctv'
    LIMIT 1;

    IF indra_system_id IS NULL THEN
        INSERT INTO systems (name, category, sort_order, is_active, needs_review, has_contingency)
        VALUES (
            'INDRA CCTV',
            NULL,
            COALESCE((SELECT MAX(sort_order) + 1 FROM systems), 1),
            true,
            false,
            false
        )
        RETURNING id INTO indra_system_id;
    END IF;

    SELECT id INTO aida_system_id
    FROM systems
    WHERE LOWER(name) = 'aida-ng'
    LIMIT 1;

    IF aida_system_id IS NULL THEN
        RAISE EXCEPTION 'AIDA-NG system not found';
    END IF;

    -- Migrate system_status_reports before deleting camera systems
    UPDATE system_status_reports
    SET system_id = indra_system_id
    WHERE system_id IN (
        SELECT id
        FROM systems
        WHERE name ~ '^INDRA CCTV - Camera [0-9]+$'
    )
      AND system_id <> indra_system_id;

    FOR camera_system IN
        SELECT id, name
        FROM systems
        WHERE name ~ '^INDRA CCTV - Camera [0-9]+$'
    LOOP
        camera_asset_name := regexp_replace(camera_system.name, '^INDRA CCTV - ', '');

        INSERT INTO assets (name, type, location, notes)
        VALUES (camera_asset_name, 'camera', 'TBD (admin review)', '')
        ON CONFLICT (name) DO NOTHING;

        SELECT id INTO camera_asset_id
        FROM assets
        WHERE name = camera_asset_name
        LIMIT 1;

        IF NOT EXISTS (
            SELECT 1
            FROM asset_system_links
            WHERE asset_id = camera_asset_id
              AND system_id = indra_system_id
              AND site = 'production'
        ) THEN
            INSERT INTO asset_system_links (asset_id, system_id, role, site)
            VALUES (camera_asset_id, indra_system_id, 'client', 'production');
        END IF;

        FOR camera_link IN
            SELECT id, asset_id, role
            FROM asset_system_links
            WHERE system_id = camera_system.id
        LOOP
            IF EXISTS (
                SELECT 1
                FROM asset_system_links
                WHERE asset_id = camera_asset_id
                  AND system_id = indra_system_id
                  AND site = 'production'
                  AND id <> camera_link.id
            ) THEN
                DELETE FROM asset_system_links WHERE id = camera_link.id;
                CONTINUE;
            END IF;

            UPDATE asset_system_links
            SET asset_id = camera_asset_id,
                system_id = indra_system_id,
                role = 'client',
                site = 'production'
            WHERE id = camera_link.id;
        END LOOP;
    END LOOP;

    FOR circuit_link IN
        SELECT l.id, l.asset_id, l.role
        FROM asset_system_links l
        JOIN systems s ON s.id = l.system_id
        WHERE s.name ~ '^International Circuits - '
    LOOP
        next_role := circuit_link.role;

        IF EXISTS (
            SELECT 1
            FROM asset_system_links
            WHERE asset_id = circuit_link.asset_id
              AND system_id = aida_system_id
              AND site = 'production'
              AND id <> circuit_link.id
        ) THEN
            DELETE FROM asset_system_links WHERE id = circuit_link.id;
            CONTINUE;
        END IF;

        IF next_role IN ('primary', 'standby') AND EXISTS (
            SELECT 1
            FROM asset_system_links
            WHERE system_id = aida_system_id
              AND role = next_role
              AND site = 'production'
              AND id <> circuit_link.id
        ) THEN
            next_role := 'client';
        END IF;

        UPDATE asset_system_links
        SET system_id = aida_system_id,
            role = next_role,
            site = 'production'
        WHERE id = circuit_link.id;
    END LOOP;

    UPDATE system_status_reports
    SET system_id = aida_system_id
    WHERE system_id IN (
        SELECT id
        FROM systems
        WHERE name ~ '^International Circuits - '
    )
      AND system_id <> aida_system_id;

    DELETE FROM systems
    WHERE name ~ '^INDRA CCTV - Camera [0-9]+$';

    DELETE FROM systems
    WHERE name ~ '^International Circuits - ';

    -- Only set has_contingency to true for specific systems, don't touch others
    UPDATE systems
    SET has_contingency = true
    WHERE LOWER(name) IN ('aida-ng', 'cadas-ats', 'cadas-ims', 'irtos')
      AND has_contingency IS DISTINCT FROM true;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_asset_system_links_unique
    ON asset_system_links(asset_id, system_id, site);

CREATE UNIQUE INDEX IF NOT EXISTS idx_asset_system_links_primary_standby
    ON asset_system_links(system_id, role, site)
    WHERE role IN ('primary', 'standby');

COMMIT;
