from db import supabase

# Role priority: higher number = more permissions
ROLE_PRIORITY = {"viewer": 1, "editor": 2, "owner": 3}

# What each role can do
ROLE_CAPABILITIES = {
    "viewer": {"view", "download"},
    "editor": {"view", "download", "rename", "move", "edit_type"},
    "owner":  {"view", "download", "rename", "move", "edit_type", "delete", "share"},
}


def get_effective_role(
    user_email: str,
    resource_id: str,
    resource_type: str,          # 'file' | 'folder'
    folder_id: str | None = None,
    resource_owner: str | None = None,
) -> str | None:
    """
    Returns the highest role the user has on the resource.
    Check order:
      1. resource_owner == user_email  → 'owner' immediately
      2. Direct permission on the resource
      3. Walk up folder chain, take highest inherited role
    """
    if resource_owner and resource_owner == user_email:
        return "owner"

    best_role: str | None = None

    # 1. Direct permission on the resource itself
    direct = supabase.table("resource_permissions") \
        .select("role") \
        .eq("resource_id", resource_id) \
        .eq("resource_type", resource_type) \
        .eq("user_email", user_email) \
        .execute()

    if direct.data:
        best_role = direct.data[0]["role"]

    # 2. Walk up folder chain (only if we haven't found 'owner' yet)
    current_folder_id = folder_id
    while current_folder_id:
        folder_perm = supabase.table("resource_permissions") \
            .select("role") \
            .eq("resource_id", current_folder_id) \
            .eq("resource_type", "folder") \
            .eq("user_email", user_email) \
            .execute()

        if folder_perm.data:
            inherited_role = folder_perm.data[0]["role"]
            if best_role is None or \
               ROLE_PRIORITY.get(inherited_role, 0) > ROLE_PRIORITY.get(best_role, 0):
                best_role = inherited_role

        # Fetch parent folder
        parent = supabase.table("file_folders") \
            .select("parent_id") \
            .eq("id", current_folder_id) \
            .execute()
        if parent.data and parent.data[0]["parent_id"]:
            current_folder_id = parent.data[0]["parent_id"]
        else:
            break

    return best_role


def can(
    user_email: str,
    action: str,                 # 'view'|'rename'|'move'|'delete'|'share'|'edit_type'
    resource_id: str,
    resource_type: str,
    folder_id: str | None = None,
    resource_owner: str | None = None,
) -> bool:
    """Returns True if user can perform action on resource."""
    # Owner always has all permissions
    if resource_owner and resource_owner == user_email:
        return True

    role = get_effective_role(
        user_email, resource_id, resource_type,
        folder_id=folder_id, resource_owner=resource_owner
    )
    if role is None:
        return False
    return action in ROLE_CAPABILITIES.get(role, set())
