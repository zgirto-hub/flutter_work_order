import json
import urllib.request
import urllib.error
import os

ONESIGNAL_APP_ID = "760f00e5-fb08-4c0c-b898-ea35737bcc21"
ONESIGNAL_API_KEY = os.environ.get("ONESIGNAL_API_KEY", "")


def send_push_notification(title: str, body: str):
    try:
        data = json.dumps({
            "app_id": ONESIGNAL_APP_ID,
            "filters": [
                {"field": "tag", "key": "role", "relation": "=", "value": "admin"},
                {"operator": "OR"},
                {"field": "tag", "key": "role", "relation": "=", "value": "tech"},
            ],
            "headings": {"en": title},
            "contents": {"en": body},
        }).encode("utf-8")
        req = urllib.request.Request(
            "https://api.onesignal.com/notifications",
            data=data,
            headers={
                "Authorization": f"Key {ONESIGNAL_API_KEY}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        response = urllib.request.urlopen(req, timeout=5)
        print(f"OneSignal response: {response.status} {response.read().decode()}")
    except urllib.error.HTTPError as e:
        print(f"OneSignal HTTP {e.code}: {e.read().decode()}")
    except Exception as e:
        print(f"OneSignal error: {e}")
