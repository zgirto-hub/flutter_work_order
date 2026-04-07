import os
import json
import urllib.request
import urllib.parse
import urllib.error
from datetime import datetime, timezone
from typing import Union, Optional


def get_admin_email() -> str:
    email = os.environ.get("ADMIN_EMAIL")
    if not email:
        raise RuntimeError("ADMIN_EMAIL environment variable is not set")
    return email


def get_api_base() -> str:
    api_base = os.environ.get("API_BASE_URL")
    if not api_base:
        raise RuntimeError("API_BASE_URL environment variable is not set")

    if not (
        api_base.startswith("http://localhost:")
        or api_base.startswith("http://127.0.0.1:")
    ):
        raise RuntimeError(
            "API_BASE_URL must start with http://localhost: or http://127.0.0.1:"
        )

    return api_base.rstrip("/")


def api_get(path: str, params: Optional[dict] = None) -> Union[dict, list]:
    api_base = get_api_base()

    if not path.startswith("/"):
        path = "/" + path

    url = api_base + path

    if params:
        query_string = urllib.parse.urlencode(params)
        url += "?" + query_string

    req = urllib.request.Request(url)
    req.add_header("Content-Type", "application/json")

    with urllib.request.urlopen(req, timeout=10) as response:
        data = response.read().decode("utf-8")
        return json.loads(data)


def api_post(path: str, body: dict) -> dict:
    api_base = get_api_base()

    if not path.startswith("/"):
        path = "/" + path

    url = api_base + path

    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
    )
    req.add_header("Content-Type", "application/json")

    with urllib.request.urlopen(req, timeout=10) as response:
        data = response.read().decode("utf-8")
        return json.loads(data)


def api_put(path: str, body: dict) -> dict:
    api_base = get_api_base()

    if not path.startswith("/"):
        path = "/" + path

    url = api_base + path

    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        method="PUT",
    )
    req.add_header("Content-Type", "application/json")

    with urllib.request.urlopen(req, timeout=10) as response:
        data = response.read().decode("utf-8")
        return json.loads(data)


def iso_now() -> str:
    return datetime.now().astimezone().isoformat()


def parse_iso(ts: str) -> datetime:
    ts_normalized = ts.replace("Z", "+00:00")
    return datetime.fromisoformat(ts_normalized)
