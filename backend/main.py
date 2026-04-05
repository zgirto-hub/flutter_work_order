print("=== THIS MAIN.PY IS RUNNING v1.10.0 ===")

import json
import os
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
)

app = FastAPI()


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
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Chrome's Private Network Access (PNA) policy requires this header in
# OPTIONS preflight responses when the client is on localhost and the server
# is on a private/CGNAT IP (e.g. 100.x.x.x Tailscale range). Without it,
# POST/PUT/DELETE with Content-Type: application/json fail silently
# ("Failed to fetch") even though CORS is otherwise configured correctly.
@app.middleware("http")
async def private_network_access_header(request: Request, call_next):
    response = await call_next(request)
    if request.method == "OPTIONS":
        response.headers["Access-Control-Allow-Private-Network"] = "true"
    return response


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


@app.get("/api/reset-password")
async def reset_password_page():
    return FileResponse("static/reset_password.html", media_type="text/html")


@app.get("/api/version")
def get_version():
    with open("version.json") as f:
        return json.load(f)
