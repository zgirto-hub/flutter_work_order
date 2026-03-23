from fastapi import APIRouter, Query
from fastapi.responses import JSONResponse

from db import supabase

router = APIRouter()


@router.get("/reports/closed-work-orders")
def get_closed_work_orders(
    technician_id: str = Query(...),
    start_date:    str = Query(...),
    end_date:      str = Query(...),
):
    try:
        resp = (
            supabase
            .from_("work_orders")
            .select("title, location, closed_at, work_order_assignments!inner(technician_id)")
            .eq("work_order_assignments.technician_id", technician_id)
            .gte("closed_at", start_date)
            .lte("closed_at", end_date)
            .order("closed_at", desc=True)
            .execute()
        )
        rows = resp.data or []
        return [
            {"title": r["title"], "location": r["location"], "closed_at": r["closed_at"]}
            for r in rows
        ]
    except Exception as e:
        return JSONResponse(status_code=500, content={"detail": str(e)})
