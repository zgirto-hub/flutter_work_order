-- Repair work orders created with a Supabase auth UUID in created_by instead of
-- the corresponding public users.id. This happened when frontend creation sent
-- the auth UUID and backend identity resolution failed, causing work orders to
-- be saved with a value that does not match the reporter filter used on refresh.

WITH repaired_rows AS (
    UPDATE work_orders AS wo
    SET created_by = u.id
    FROM users AS u
    WHERE wo.created_by::text = u.auth_id::text
      AND wo.created_by::text != u.id::text
    RETURNING wo.id
)
INSERT INTO user_activity_log (
    user_email,
    user_name,
    category,
    action,
    target_label,
    target_id,
    detail
)
SELECT
    'system@migration.local',
    'system',
    'work_order',
    'migration_repaired_created_by',
    'created_by repaired',
    repaired_rows.id::text,
    'Repaired work_orders.created_by from auth UUID to users.id'
FROM repaired_rows;
