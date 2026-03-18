-- Find orphaned comments (comments where work_order no longer exists)
SELECT 
    wc.id,
    wc.work_order_id,
    wc.author_email,
    wc.created_at
FROM work_order_comments wc
WHERE NOT EXISTS (
    SELECT 1 FROM work_orders wo WHERE wo.id = wc.work_order_id
);

-- Count orphaned comments
SELECT COUNT(*) as orphaned_comment_count
FROM work_order_comments wc
WHERE NOT EXISTS (
    SELECT 1 FROM work_orders wo WHERE wo.id = wc.work_order_id
);

-- Delete orphaned comments (uncomment when ready)
-- DELETE FROM work_order_comments 
-- WHERE NOT EXISTS (
--     SELECT 1 FROM work_orders wo WHERE wo.id = work_order_comments.work_order_id
-- );
