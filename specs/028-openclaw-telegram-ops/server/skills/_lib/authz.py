import os


def assert_authorized() -> str:
    caller_id = os.environ.get("OPENCLAW_CALLER_ID")
    if not caller_id:
        raise PermissionError("unauthorized caller")
    return caller_id
