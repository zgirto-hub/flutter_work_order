from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from db import supabase

router = APIRouter()


class ItTeamCreate(BaseModel):
    name: str
    sort_order: Optional[int] = 0


class ItTeamUpdate(BaseModel):
    name: Optional[str] = None
    sort_order: Optional[int] = None


@router.get("/it-teams")
async def list_it_teams():
    """Get all IT teams sorted by sort_order"""
    result = supabase.table("it_teams") \
        .select("*") \
        .order("sort_order") \
        .execute()
    return {"it_teams": result.data or []}


@router.post("/it-teams")
async def create_it_team(body: ItTeamCreate):
    """Create a new IT team"""
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="IT team name is required")
    
    # Check if already exists
    existing = supabase.table("it_teams") \
        .select("id") \
        .eq("name", name) \
        .execute()
    if existing.data:
        raise HTTPException(status_code=400, detail=f"IT team '{name}' already exists")
    
    # Get max sort_order if not provided
    if body.sort_order is None:
        max_order = supabase.table("it_teams") \
            .select("sort_order") \
            .order("sort_order", desc=True) \
            .limit(1) \
            .execute()
        next_order = (max_order.data[0]["sort_order"] + 1) if max_order.data else 1
    else:
        next_order = body.sort_order
    
    result = supabase.table("it_teams").insert({
        "name": name,
        "sort_order": next_order
    }).execute()
    
    return {"it_team": result.data[0] if result.data else None}


@router.patch("/it-teams/{it_team_id}")
async def update_it_team(it_team_id: str, body: ItTeamUpdate):
    """Update an IT team"""
    update_data = {}
    
    if body.name is not None:
        name = body.name.strip()
        if not name:
            raise HTTPException(status_code=400, detail="IT team name cannot be empty")
        
        # Check if name already exists for different team
        existing = supabase.table("it_teams") \
            .select("id") \
            .eq("name", name) \
            .neq("id", it_team_id) \
            .execute()
        if existing.data:
            raise HTTPException(status_code=400, detail=f"IT team '{name}' already exists")
        
        update_data["name"] = name
    
    if body.sort_order is not None:
        update_data["sort_order"] = body.sort_order
    
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update")
    
    result = supabase.table("it_teams") \
        .update(update_data) \
        .eq("id", it_team_id) \
        .execute()
    
    if not result.data:
        raise HTTPException(status_code=404, detail="IT team not found")
    
    return {"it_team": result.data[0]}


@router.delete("/it-teams/{it_team_id}")
async def delete_it_team(it_team_id: str):
    """Delete an IT team"""
    # Check if team exists
    existing = supabase.table("it_teams") \
        .select("name") \
        .eq("id", it_team_id) \
        .execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="IT team not found")
    
    team_name = existing.data[0]["name"]
    
    # Check if team is used by any employees
    emp_check = supabase.table("employees") \
        .select("id") \
        .eq("it_team", team_name) \
        .limit(1) \
        .execute()
    if emp_check.data:
        raise HTTPException(
            status_code=400,
            detail="Cannot delete: IT team is assigned to employees"
        )
    
    # Delete the team
    supabase.table("it_teams") \
        .delete() \
        .eq("id", it_team_id) \
        .execute()
    
    return {"deleted": True, "name": team_name}
