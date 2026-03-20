CREATE OR REPLACE FUNCTION get_closed_work_orders_report(
  emp_id     UUID,
  start_date DATE,
  end_date   DATE
)
RETURNS TABLE (title TEXT, location TEXT, closed_at TIMESTAMPTZ)
LANGUAGE sql
AS $$
  SELECT
    wo.title,
    wo.location,
    wo.closed_at
  FROM work_order_assignments a
  JOIN work_orders wo ON wo.id = a.work_order_id
  WHERE a.fixer_id = emp_id
    AND wo.closed_at::date >= start_date
    AND wo.closed_at::date <= end_date
  ORDER BY wo.closed_at DESC;
$$;
