-- Test CASCADE DELETE for work_order_comments
-- Run this in Supabase SQL editor

-- Step 1: Find a work order with comments and get its ID
-- (Run this and copy the id value)
SELECT 
    wo.id,
    wo.title,
    wo.status,
    COUNT(wc.id) as comment_count
FROM work_orders wo
LEFT JOIN work_order_comments wc ON wc.work_order_id = wo.id
GROUP BY wo.id, wo.title, wo.status
HAVING COUNT(wc.id) > 0
ORDER BY wo.date_created DESC
LIMIT 1;

-- Step 2: After running Step 1, replace 'YOUR_WORK_ORDER_ID_HERE' with the actual ID
-- Then UNCOMMENT and run this line:
-- DELETE FROM work_orders WHERE id = 'YOUR_WORK_ORDER_ID_HERE';

-- Step 3: Verify comments are deleted (should return 0 rows)
-- Replace 'YOUR_WORK_ORDER_ID_HERE' with the same ID, then UNCOMMENT and run:
-- SELECT * FROM work_order_comments WHERE work_order_id = 'YOUR_WORK_ORDER_ID_HERE';
