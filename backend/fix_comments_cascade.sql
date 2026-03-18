-- Add CASCADE DELETE for work_order_comments when work_order is deleted
-- This ensures comments are automatically deleted when a work order is deleted
-- Run this in Supabase SQL editor

DO $$
BEGIN
    -- Check if the foreign key already exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'work_order_comments_work_order_id_fkey'
        AND table_name = 'work_order_comments'
    ) THEN
        -- Add the foreign key with cascade delete
        ALTER TABLE work_order_comments 
        ADD CONSTRAINT work_order_comments_work_order_id_fkey 
        FOREIGN KEY (work_order_id) 
        REFERENCES work_orders(id) 
        ON DELETE CASCADE;
        
        RAISE NOTICE 'Foreign key with CASCADE added successfully';
    ELSE
        -- Check if current FK has cascade
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints tc
            JOIN information_schema.referential_constraints rc 
                ON tc.constraint_name = rc.constraint_name
            WHERE tc.constraint_name = 'work_order_comments_work_order_id_fkey'
            AND rc.delete_rule = 'CASCADE'
        ) THEN
            -- Drop and recreate with cascade
            ALTER TABLE work_order_comments 
            DROP CONSTRAINT work_order_comments_work_order_id_fkey,
            ADD CONSTRAINT work_order_comments_work_order_id_fkey 
            FOREIGN KEY (work_order_id) 
            REFERENCES work_orders(id) 
            ON DELETE CASCADE;
            
            RAISE NOTICE 'Foreign key updated with CASCADE';
        ELSE
            RAISE NOTICE 'Foreign key with CASCADE already exists';
        END IF;
    END IF;
END $$;
