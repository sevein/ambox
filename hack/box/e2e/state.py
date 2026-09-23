from __future__ import annotations

from dataclasses import dataclass
from dataclasses import field
from typing import Any


@dataclass
class Verification:
    pipeline_uuid: str = ""
    spaces: list[dict[str, Any]] = field(default_factory=list)
    locations: list[dict[str, Any]] = field(default_factory=list)
    packages: list[dict[str, Any]] = field(default_factory=list)
    transfer_name: str = ""
    transfer_uuid: str = ""
    sip_uuid: str = ""
    transfer_jobs: list[dict[str, Any]] = field(default_factory=list)
