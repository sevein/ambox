from __future__ import annotations

from dataclasses import dataclass
from dataclasses import field
from typing import Any


@dataclass
class Verification:
    transfer_name: str = ""
    transfer_uuid: str = ""
    sip_uuid: str = ""
    transfer_jobs: list[dict[str, Any]] = field(default_factory=list)
