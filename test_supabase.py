import os
from supabase import create_client

SUPABASE_URL = "https://rydrqsjofoulwdtwfbgv.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ5ZHJxc2pvZm91bHdkdHdmYmd2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIxNDE4OTIsImV4cCI6MjA4NzcxNzg5Mn0.FK65DZA7KnZd3Hz_hYOFFFMh1tyQtFiJhY3TzHleFeA"

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# Test simple select
print("Testing simple select...")
result = supabase.table("work_orders").select("*").execute()
print(f"Rows: {len(result.data)}")
for row in result.data:
    print(row)

# Test join
print("\nTesting join...")
try:
    result2 = supabase.table("work_orders").select("""
        *,
        work_order_assignments (
            fixer_id,
            assigned_at,
            assigned_by,
            users!work_order_assignments_fixer_id_fkey (
                id,
                email,
                full_name
            )
        )
    """).execute()
    print(f"Rows with join: {len(result2.data)}")
except Exception as e:
    print(f"Join error: {e}")