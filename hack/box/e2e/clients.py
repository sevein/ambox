from __future__ import annotations

import json
import urllib.error
import urllib.request
from collections import deque
from dataclasses import dataclass
from dataclasses import field
from datetime import datetime
from datetime import timezone
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ResponseRecord:
    timestamp: str
    method: str
    path: str
    status: int
    body: Any


@dataclass
class API:
    base_url: str
    authorization: str
    history: deque[ResponseRecord] = field(default_factory=lambda: deque(maxlen=100))

    def request(
        self,
        path: str,
        *,
        method: str = "GET",
        payload: dict[str, Any] | None = None,
    ) -> tuple[int, Any]:
        data = None
        headers = {
            "Accept": "application/json",
            "Authorization": self.authorization,
        }
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"

        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        try:
            response = urllib.request.urlopen(request, timeout=30)
        except urllib.error.HTTPError as error:
            response = error

        with response:
            raw = response.read().decode("utf-8", errors="replace")
            status = response.status
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = raw

        self.history.append(
            ResponseRecord(
                timestamp=datetime.now(timezone.utc).isoformat(),
                method=method,
                path=path,
                status=status,
                body=body,
            )
        )
        return status, body

    def write_history(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(
                [record.__dict__ for record in self.history],
                indent=2,
                default=str,
            )
            + "\n",
            encoding="utf-8",
        )


@dataclass(frozen=True)
class Services:
    dashboard: API
    storage: API
    dashboard_url: str
    sftp_port: int
    dashboard_user: str
    dashboard_password: str
    container_name: str
