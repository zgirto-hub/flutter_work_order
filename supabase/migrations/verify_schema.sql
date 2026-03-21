-- =============================================================
-- Schema Verification Script
-- Run in Supabase SQL Editor to verify all migrations applied
-- =============================================================

-- 1. Check all expected tables exist
SELECT 'TABLES' AS check_type,
       table_name,
       CASE WHEN table_name IS NOT NULL THEN 'OK' ELSE 'MISSING' END AS status
FROM (
    VALUES
        ('departments'),
        ('users'),
        ('technician_departments'),
        ('work_orders'),
        ('work_order_assignments'),
        ('work_order_status_logs'),
        ('work_order_comments'),
        ('work_order_attachments'),
        ('work_order_watchers'),
        ('notifications'),
        ('notification_delivery_logs'),
        ('notification_preferences')
) AS expected(table_name)
LEFT JOIN information_schema.tables t
    ON t.table_name = expected.table_name
    AND t.table_schema = 'public'
ORDER BY expected.table_name;

-- 2. Check users table has department_id column (from 20260321_add_user_department)
SELECT 'COLUMN CHECK' AS check_type,
       'users.department_id' AS item,
       CASE WHEN column_name IS NOT NULL THEN 'OK' ELSE 'MISSING' END AS status
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'department_id';

-- 3. Check technician rename applied (technician_departments exists, fixer_departments gone)
SELECT 'RENAME CHECK' AS check_type,
       'technician_departments' AS item,
       CASE WHEN EXISTS (
           SELECT 1 FROM information_schema.tables
           WHERE table_schema = 'public' AND table_name = 'technician_departments'
       ) THEN 'OK' ELSE 'MISSING' END AS status
UNION ALL
SELECT 'RENAME CHECK',
       'fixer_departments (should be gone)',
       CASE WHEN NOT EXISTS (
           SELECT 1 FROM information_schema.tables
           WHERE table_schema = 'public' AND table_name = 'fixer_departments'
       ) THEN 'OK' ELSE 'STILL EXISTS' END;

-- 4. Check user_type allows 'technician'
SELECT 'USER_TYPE CHECK' AS check_type,
       'technician in check constraint' AS item,
       CASE WHEN EXISTS (
           SELECT 1 FROM information_schema.check_constraints
           WHERE constraint_schema = 'public'
           AND check_clause LIKE '%technician%'
       ) THEN 'OK' ELSE 'MISSING' END AS status;

-- 5. Check RLS is enabled on work_orders
SELECT 'RLS CHECK' AS check_type,
       'work_orders RLS enabled' AS item,
       CASE WHEN rowsecurity THEN 'OK' ELSE 'DISABLED' END AS status
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'work_orders';

-- 6. Check RLS policies exist
SELECT 'RLS POLICIES' AS check_type,
       policyname AS item,
       'OK' AS status
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'work_orders'
ORDER BY policyname;

-- 7. Check report function exists
SELECT 'FUNCTION CHECK' AS check_type,
       'get_closed_work_orders_report' AS item,
       CASE WHEN EXISTS (
           SELECT 1 FROM information_schema.routines
           WHERE routine_schema = 'public'
           AND routine_name = 'get_closed_work_orders_report'
       ) THEN 'OK' ELSE 'MISSING' END AS status;

-- 8. Row counts
SELECT 'ROW COUNTS' AS check_type,
       'departments' AS item,
       COUNT(*)::TEXT AS status FROM public.departments
UNION ALL
SELECT 'ROW COUNTS', 'users', COUNT(*)::TEXT FROM public.users
UNION ALL
SELECT 'ROW COUNTS', 'work_orders', COUNT(*)::TEXT FROM public.work_orders;
