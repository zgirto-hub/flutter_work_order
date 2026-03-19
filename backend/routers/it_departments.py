from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional, List

from db import supabase

router = APIRouter()


class AssignReporterBody(BaseModel):
    it_department: str
    reporter_department: str


@router.get("/it-departments")
async def get_it_departments():
    """Get list of all IT departments"""
    result = supabase.table("employees") \
        .select("department") \
        .eq("user_type", "tech") \
        .execute()
    departments = list(set([r.get("department") for r in (result.data or []) if r.get("department")]))
    return {"departments": sorted(departments)}


@router.get("/it-department-reporters")
async def get_it_department_reporters(email: str = Query(...)):
    """Get which departments an IT tech's team supports"""
    normalized = email.strip().lower()
    
    # Get tech's IT department
    emp_result = supabase.table("employees") \
        .select("it_team, department") \
        .eq("email", normalized) \
        .execute()
    
    if not emp_result.data:
        # Try by user_profiles
        up_result = supabase.table("user_profiles") \
            .select("email") \
            .eq("email", normalized) \
            .execute()
        if up_result.data:
            # Get first matching employee
            all_emps = supabase.table("employees") \
                .select("it_team, department") \
                .limit(1) \
                .execute()
            if all_emps.data:
                emp_result.data = all_emps.data
    
    it_dept = None
    if emp_result.data:
        it_dept = emp_result.data[0].get("it_team") or emp_result.data[0].get("department")
    
    if not it_dept:
        return {"it_department": None, "reporter_departments": []}
    
    # Get reporter departments for this IT team
    result = supabase.table("it_department_reporters") \
        .select("reporter_department") \
        .eq("it_department", it_dept) \
        .execute()
    
    reporters = [r.get("reporter_department") for r in (result.data or [])]
    
    return {
        "it_department": it_dept,
        "reporter_departments": reporters
    }


@router.get("/reporter-departments")
async def get_reporter_departments(it_department: str = Query(...)):
    """Get all reporter departments for an IT department"""
    result = supabase.table("it_department_reporters") \
        .select("reporter_department") \
        .eq("it_department", it_department) \
        .execute()
    return {"departments": [r.get("reporter_department") for r in (result.data or [])]}


@router.post("/it-department-reporters")
async def assign_reporter_department(body: AssignReporterBody):
    """Assign a reporter department to an IT department"""
    try:
        supabase.table("it_department_reporters").upsert({
            "it_department": body.it_department,
            "reporter_department": body.reporter_department,
        }).execute()
        return {"status": "assigned"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/it-department-reporters")
async def remove_reporter_department(
    it_department: str = Query(...),
    reporter_department: str = Query(...),
):
    """Remove a reporter department from an IT department"""
    supabase.table("it_department_reporters") \
        .delete() \
        .eq("it_department", it_department) \
        .eq("reporter_department", reporter_department) \
        .execute()
    return {"status": "removed"}


@router.get("/it-department-reporters/all")
async def get_all_it_reporter_mappings():
    """Get all IT department to reporter mappings"""
    result = supabase.table("it_department_reporters") \
        .select("*") \
        .execute()
    return {"mappings": result.data or []}


@router.patch("/employees/{email}/it-team")
async def update_employee_it_team(email: str, it_team: str = Query(...)):
    """Update an employee's IT team"""
    normalized = email.strip().lower()
    supabase.table("employees").update({"it_team": it_team}).eq("email", normalized).execute()
    return {"status": "updated"}
