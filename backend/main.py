print("=== THIS MAIN.PY IS RUNNING v1.10.0 ===")

import json
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from routers import documents, folders, notifications, users, work_orders, fixer_departments, departments, employees

app = FastAPI()

UPLOAD_DIR = "uploaded_files"
os.makedirs(UPLOAD_DIR, exist_ok=True)

app.mount("/files", StaticFiles(directory=UPLOAD_DIR), name="files")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(documents.router, prefix="/api")
app.include_router(folders.router, prefix="/api")
app.include_router(users.router, prefix="/api")
app.include_router(work_orders.router, prefix="/api")
app.include_router(notifications.router, prefix="/api")
app.include_router(fixer_departments.router, prefix="/api")
app.include_router(departments.router, prefix="/api")
app.include_router(employees.router, prefix="/api")


@app.get("/api/version")
def get_version():
    with open("version.json") as f:
        return json.load(f)


@app.get("/api/debug/env")
def debug_env():
    import os
    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_KEY", "")
    return {
        "url": url,
        "key_prefix": key[:10] + "..." if key else "",
        "key_length": len(key),
    }
