import os
import sys
sys.path.insert(0, '/home/zorin/Development/flutter_work_order/backend')

os.environ['SUPABASE_URL'] = 'https://rydrqsjofoulwdtwfbgv.supabase.co'
os.environ['SUPABASE_KEY'] = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ5ZHJxc2pvZm91bHdkdHdmYmd2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjE0MTg5MiwiZXhwIjoyMDg3NzE3ODkyfQ.HvebR7mHIz2Dp4HRiLf6nVrzbqgeIX5XLc3NuVexwII'

from main import app
from fastapi.testclient import TestClient

client = TestClient(app)

try:
    response = client.post("/api/work-orders", json={
        "job_no": "WO-TEST-999",
        "title": "Test",
        "description": "Test",
        "location": "Test",
        "mobile_number": "",
        "department_id": "7a6c0f1a-46bc-4a24-a1e4-8fdc4861e94f",
        "type": "Technical",
        "status": "Pending",
        "created_by": "57f6a85d-92ce-48ce-a909-4de7ad524f3d",
        "created_by_email": "test@test.com",
        "assigned_fixer_ids": []
    })
    print(f"Status: {response.status_code}")
    print(f"Response: {response.text[:500]}")
except Exception as e:
    import traceback
    print(f"Error: {type(e).__name__}: {e}")
    traceback.print_exc()
