-- =============================================================
-- Enable Row Level Security on work_orders
-- =============================================================

ALTER TABLE work_orders ENABLE ROW LEVEL SECURITY;

-- Reporter: can only see work orders they created
CREATE POLICY "reporter_own_wos" ON work_orders
FOR SELECT USING (
    (SELECT user_type FROM users WHERE auth_id = auth.uid()) = 'reporter'
    AND created_by = (SELECT id FROM users WHERE auth_id = auth.uid())
);

-- Technician: can only see work orders in their assigned departments
CREATE POLICY "technician_department_wos" ON work_orders
FOR SELECT USING (
    (SELECT user_type FROM users WHERE auth_id = auth.uid()) = 'technician'
    AND department_id IN (
        SELECT department_id FROM technician_departments
        WHERE technician_id = (SELECT id FROM users WHERE auth_id = auth.uid())
    )
);

-- Admin: can see all work orders
CREATE POLICY "admin_all_wos" ON work_orders
FOR SELECT USING (
    (SELECT user_type FROM users WHERE auth_id = auth.uid()) = 'admin'
);

-- Any authenticated user can create work orders
CREATE POLICY "authenticated_insert_wos" ON work_orders
FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Admin and technician can update work orders
CREATE POLICY "admin_technician_update_wos" ON work_orders
FOR UPDATE USING (
    (SELECT user_type FROM users WHERE auth_id = auth.uid()) IN ('admin', 'technician')
);

-- Only admin can delete work orders
CREATE POLICY "admin_delete_wos" ON work_orders
FOR DELETE USING (
    (SELECT user_type FROM users WHERE auth_id = auth.uid()) = 'admin'
);
