import json
import urllib.request
import urllib.error
import os
from typing import Optional

ONESIGNAL_APP_ID = "760f00e5-fb08-4c0c-b898-ea35737bcc21"
ONESIGNAL_API_KEY = os.environ.get("ONESIGNAL_API_KEY", "")


def _post_onesignal(payload: dict) -> Optional[dict]:
    if not ONESIGNAL_API_KEY:
        print("OneSignal skipped: ONESIGNAL_API_KEY is empty")
        return None
    try:
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            "https://api.onesignal.com/notifications",
            data=data,
            headers={
                "Authorization": f"Key {ONESIGNAL_API_KEY}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        response = urllib.request.urlopen(req, timeout=7)
        raw = response.read().decode()
        print(f"OneSignal response: {response.status} {raw}")
        try:
            return json.loads(raw)
        except Exception:
            return {"raw": raw}
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"OneSignal HTTP {e.code}: {body}")
        return {"error": body, "status": e.code}
    except Exception as e:
        print(f"OneSignal error: {e}")
        return {"error": str(e)}


def send_push_notification(title: str, body: str):
    _post_onesignal({
        "app_id": ONESIGNAL_APP_ID,
        "filters": [
            {"field": "tag", "key": "role", "relation": "=", "value": "admin"},
            {"operator": "OR"},
            {"field": "tag", "key": "role", "relation": "=", "value": "tech"},
        ],
        "headings": {"en": title},
        "contents": {"en": body},
    })


def send_push_to_external_ids(
    *,
    title: str,
    body: str,
    external_ids: list[str],
    data: Optional[dict] = None,
):
    recipients = sorted({(e or "").strip().lower() for e in external_ids if (e or "").strip()})
    if not recipients:
        return {"status": "skipped", "reason": "no_recipients"}

    payload = {
        "app_id": ONESIGNAL_APP_ID,
        "include_aliases": {
            "external_id": recipients,
        },
        "target_channel": "push",
        "headings": {"en": title},
        "contents": {"en": body},
    }
    if data:
        payload["data"] = data
    result = _post_onesignal(payload)
    return result or {"status": "queued"}
