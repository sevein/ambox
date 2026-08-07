from __future__ import annotations

import base64
import os
import subprocess
import time
import uuid
from typing import Any

import pytest
from clients import Services
from pytest_bdd import given
from pytest_bdd import then
from pytest_bdd import when
from state import Verification

TERMINAL_FAILURES = {"FAILED", "REJECTED", "USER_INPUT"}
VIRUS_SCAN_LINK_ID = "1c2550f1-3fc0-45d8-8bc4-4c06d720283b"


def require_uuid(value: Any, label: str) -> str:
    try:
        parsed = uuid.UUID(str(value))
    except (TypeError, ValueError, AttributeError):
        pytest.fail(f"Expected {label} UUID, got {value!r}")
    return str(parsed)


def failed_jobs(ambox: Services, unit_uuid: str) -> str:
    status, body = ambox.dashboard.request(f"/api/v2beta/jobs/{unit_uuid}/?detailed")
    if status != 200 or not isinstance(body, list):
        return f"jobs endpoint returned HTTP {status}: {body}"

    lines = []
    for job in body:
        if job.get("status") != "FAILED":
            continue
        lines.append(f"failed job: {job.get('name')} (link {job.get('link_uuid')})")
        for task in job.get("tasks", []):
            lines.append(
                f"  task: {task.get('file_name')} (exit code {task.get('exit_code')})"
            )
    return "\n".join(lines) or "no failed jobs reported"


def poll_unit(
    ambox: Services,
    unit_type: str,
    unit_uuid: str,
    deadline: float,
    interval: float,
) -> dict[str, Any]:
    path = f"/api/{unit_type}/status/{unit_uuid}/"
    previous = None

    while time.monotonic() < deadline:
        status_code, body = ambox.dashboard.request(path)
        if status_code == 400:
            summary = "waiting for status"
        else:
            assert status_code == 200, body
            assert isinstance(body, dict), body
            state = str(body.get("status", ""))
            microservice = str(body.get("microservice", ""))
            summary = f"{state or 'PROCESSING'}: {microservice}"
            if state == "COMPLETE":
                print(f"{unit_type}_status={summary}")
                return body
            if state in TERMINAL_FAILURES:
                details = failed_jobs(ambox, unit_uuid)
                pytest.fail(f"{unit_type} ended in {summary}\n{details}")
            assert state in {"", "PROCESSING"}, f"Unknown status: {state!r}"

        if summary != previous:
            print(f"{unit_type}_status={summary}", flush=True)
            previous = summary
        time.sleep(interval)

    pytest.fail(f"Timed out waiting for {unit_type} {unit_uuid}")


def get_jobs(ambox: Services, unit_uuid: str, label: str) -> list[dict[str, Any]]:
    status, body = ambox.dashboard.request(f"/api/v2beta/jobs/{unit_uuid}/?detailed")
    assert status == 200, body
    assert isinstance(body, list) and body, f"Expected {label} jobs"

    failed = [job for job in body if job.get("status") == "FAILED"]
    assert not failed, f"Failed {label} jobs: {failed}"

    task_count = sum(
        len(job.get("tasks", [])) for job in body if isinstance(job.get("tasks"), list)
    )
    assert task_count > 0, f"Expected tasks nested under {label} jobs"
    print(f"{label}_jobs={len(body)} {label}_tasks={task_count}")
    return body


@given("ambox is running")
def ambox_is_running(ambox: Services) -> None:
    assert ambox


@given("the ClamAV daemon shares its version")
def clamav_shares_its_version(ambox: Services) -> None:
    probe = """
import socket
s = socket.socket(socket.AF_UNIX)
s.settimeout(10)
s.connect("/var/run/clamav/clamd.ctl")
s.sendall(b"nVERSION\\n")
print(s.recv(4096).decode(), end="")
"""
    deadline = time.monotonic() + 120
    last_error = "clamd socket is not ready"
    while time.monotonic() < deadline:
        result = subprocess.run(
            [
                "docker",
                "exec",
                ambox.container_name,
                "/venv/bin/python",
                "-c",
                probe,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout:
            assert result.stdout.startswith("ClamAV "), (
                f"Unexpected clamd VERSION response: {result.stdout!r}"
            )
            assert result.stdout.count("/") >= 2, (
                f"Incomplete clamd VERSION response: {result.stdout!r}"
            )
            print(f"clamav_version={result.stdout.strip()}")
            return
        last_error = result.stderr.strip() or f"exit status {result.returncode}"
        time.sleep(2)

    pytest.fail(f"Timed out waiting for clamd VERSION: {last_error}")


@when("the bundled pictures are submitted with automated processing")
def submit_pictures(ambox: Services, verification: Verification) -> None:
    transfer_path = os.getenv(
        "AMBOX_TRANSFER_PATH",
        "/home/archivematica/sampledata/Images/pictures",
    )
    encoded_path = base64.b64encode(transfer_path.encode()).decode()
    verification.transfer_name = f"ambox-e2e-{int(time.time())}-{os.getpid()}"
    payload = {
        "name": verification.transfer_name,
        "type": "standard",
        "accession": "",
        "access_system_id": "",
        "processing_config": "automated",
        "auto_approve": True,
        "path": encoded_path,
        "metadata_set_id": "",
    }

    status, body = ambox.dashboard.request(
        "/api/v2beta/package/", method="POST", payload=payload
    )
    assert status == 202, body
    assert isinstance(body, dict), body
    verification.transfer_uuid = require_uuid(body.get("id"), "transfer")
    print(f"transfer_uuid={verification.transfer_uuid}")


@then("the transfer completes")
def transfer_completes(ambox: Services, verification: Verification) -> None:
    timeout = float(os.getenv("AMBOX_E2E_TIMEOUT", "600"))
    interval = float(os.getenv("AMBOX_E2E_POLL_INTERVAL", "2"))
    result = poll_unit(
        ambox,
        "transfer",
        verification.transfer_uuid,
        time.monotonic() + timeout,
        interval,
    )
    verification.sip_uuid = require_uuid(result.get("sip_uuid"), "SIP")
    print(f"sip_uuid={verification.sip_uuid}")


@then("transfer jobs and tasks are exposed by the API")
def transfer_jobs_exist(ambox: Services, verification: Verification) -> None:
    verification.transfer_jobs = get_jobs(ambox, verification.transfer_uuid, "transfer")


@then("the ClamAV scan completes successfully")
def clamav_scan_completes(verification: Verification) -> None:
    matches = [
        job
        for job in verification.transfer_jobs
        if job.get("link_uuid") == VIRUS_SCAN_LINK_ID
    ]
    assert len(matches) == 1, "Expected one virus-scan job in the transfer"

    job = matches[0]
    tasks = job.get("tasks")
    assert job.get("status") == "COMPLETE", job
    assert isinstance(tasks, list) and tasks, job
    assert all(task.get("exit_code") == 0 for task in tasks), tasks
    print(f"virus_scan_tasks={len(tasks)}")


@then("the SIP completes ingest")
def sip_completes_ingest(ambox: Services, verification: Verification) -> None:
    timeout = float(os.getenv("AMBOX_E2E_TIMEOUT", "600"))
    interval = float(os.getenv("AMBOX_E2E_POLL_INTERVAL", "2"))
    poll_unit(
        ambox,
        "ingest",
        verification.sip_uuid,
        time.monotonic() + timeout,
        interval,
    )


@then("ingest jobs and tasks are exposed by the API")
def ingest_jobs_exist(ambox: Services, verification: Verification) -> None:
    get_jobs(ambox, verification.sip_uuid, "ingest")


@then("the AIP is uploaded to Storage Service")
def aip_is_uploaded(ambox: Services, verification: Verification) -> None:
    timeout = float(os.getenv("AMBOX_E2E_TIMEOUT", "600"))
    interval = float(os.getenv("AMBOX_E2E_POLL_INTERVAL", "2"))
    deadline = time.monotonic() + timeout
    path = f"/api/v2/file/{verification.sip_uuid}/"

    while time.monotonic() < deadline:
        status, body = ambox.storage.request(path)
        if status == 200:
            assert isinstance(body, dict), body
            assert body.get("package_type") == "AIP", body
            if body.get("status") == "UPLOADED":
                assert require_uuid(body.get("uuid"), "AIP") == verification.sip_uuid
                print(
                    f"aip_uuid={body['uuid']} aip_status={body['status']} "
                    f"aip_size={body.get('size')}"
                )
                return
        else:
            assert status in {400, 404}, body
        time.sleep(interval)

    pytest.fail(f"Timed out waiting for uploaded AIP {verification.sip_uuid}")
