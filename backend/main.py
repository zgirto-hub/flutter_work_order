print("=== THIS MAIN.PY IS RUNNING v1.10.0 ===")

import asyncio
import json
import os
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, FileResponse

from routers import (
    files,
    folders,
    notifications,
    users,
    work_orders,
    departments,
    recurring_inspections,
    reports,
    department_routes,
    document_registry,
    payment_certificates,
    system_status,
    signatures,
    ai_assist,
    ai_insights,
    ai_search,
    letters_v2,
    manuals,
    patterns,
    settings,
    asset_registry,
    systems,
    ai_providers,
    documents,
    admin_rag_diagnostics,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    from services.pattern_engine import seed_built_in_rules
    from services.ai_queue import (
        worker as ai_worker,
        initialize as ai_queue_init,
        shutdown as ai_queue_shutdown,
    )
    from services.ai_providers.resolver import _migrate_default_provider

    await seed_built_in_rules()
    await _migrate_default_provider()
    ai_queue_init()
    worker_task = asyncio.create_task(ai_worker())
    print("[ai_queue] Worker started")
    yield
    worker_task.cancel()
    try:
        await worker_task
    except asyncio.CancelledError:
        pass
    ai_queue_shutdown()
    print("[ai_queue] Worker stopped")


app = FastAPI(lifespan=lifespan)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    body = await request.body()
    print(f"=== 422 VALIDATION ERROR ===")
    print(f"URL: {request.url}")
    print(f"Body: {body.decode()}")
    print(f"Errors: {exc.errors()}")
    return JSONResponse(status_code=422, content={"detail": exc.errors()})


UPLOAD_DIR = "uploaded_files"
os.makedirs(UPLOAD_DIR, exist_ok=True)

app.mount("/files", StaticFiles(directory=UPLOAD_DIR), name="files")

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=".*",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    allow_private_network=True,
)


app.include_router(files.router, prefix="/api")
app.include_router(folders.router, prefix="/api")
app.include_router(users.router, prefix="/api")
app.include_router(work_orders.router, prefix="/api")
app.include_router(notifications.router, prefix="/api")
app.include_router(departments.router, prefix="/api")
app.include_router(department_routes.router, prefix="/api")
app.include_router(recurring_inspections.router, prefix="/api")
app.include_router(reports.router, prefix="/api")
app.include_router(document_registry.router, prefix="/api")
app.include_router(payment_certificates.router, prefix="/api")
app.include_router(system_status.router, prefix="/api")
app.include_router(signatures.router, prefix="/api")
app.include_router(ai_assist.router, prefix="/api")
app.include_router(ai_insights.router, prefix="/api")
app.include_router(ai_search.router, prefix="/api")
app.include_router(letters_v2.router, prefix="/api")
app.include_router(manuals.router, prefix="/api")
app.include_router(patterns.router, prefix="/api")
app.include_router(ai_providers.router, prefix="/api", tags=["ai-providers"])
app.include_router(settings.router, prefix="/api")
app.include_router(asset_registry.router, prefix="/api")
app.include_router(systems.router, prefix="/api", tags=["systems"])
app.include_router(documents.router, prefix="/api", tags=["documents"])
app.include_router(admin_rag_diagnostics.router, prefix="/api")


@app.get("/api/reset-password")
async def reset_password_page():
    return FileResponse("static/reset_password.html", media_type="text/html")


@app.get("/api/version")
def get_version():
    with open("version.json") as f:
        return json.load(f)
