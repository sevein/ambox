from __future__ import annotations

import base64
import os
import shutil
import subprocess
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any

import pytest
from clients import Services
from pytest_bdd import given
from pytest_bdd import then
from pytest_bdd import when
from state import Verification

TERMINAL_FAILURES = {"FAILED", "REJECTED", "USER_INPUT"}
VIRUS_SCAN_LINK_ID = "1c2550f1-3fc0-45d8-8bc4-4c06d720283b"
AIP_STORE_ROOT = Path("/var/archivematica/sharedDirectory/www/AIPsStore")
DIP_STORE_ROOT = Path("/var/archivematica/sharedDirectory/www/DIPsStore")
BOX_ROOT = Path(__file__).resolve().parents[2]
SAMPLE_TRANSFER = (
    BOX_ROOT.parent
    / "submodules"
    / "archivematica-sampledata"
    / "SampleTransfers"
    / "Images"
    / "pictures"
)
SFTP_PRIVATE_KEY = BOX_ROOT / "test" / "ssh_user_ed25519_key"
SFTP_KNOWN_HOSTS = BOX_ROOT / "test" / "known_hosts"


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


def related_dip(ambox: Services, aip: dict[str, Any]) -> dict[str, Any] | None:
    related_packages = aip.get("related_packages")
    assert isinstance(related_packages, list), aip

    for resource_uri in related_packages:
        assert isinstance(resource_uri, str), aip
        status, package = ambox.storage.request(resource_uri)
        assert status == 200, package
        assert isinstance(package, dict), package
        if package.get("package_type") == "DIP":
            return package
    return None


def assert_package_readable(
    ambox: Services,
    package: dict[str, Any],
    package_type: str,
    store_root: Path,
) -> None:
    assert package.get("package_type") == package_type, package
    assert package.get("status") == "UPLOADED", package
    current_full_path = package.get("current_full_path")
    assert isinstance(current_full_path, str), package
    package_path = Path(current_full_path)
    assert package_path.is_relative_to(store_root), package

    result = subprocess.run(
        [
            "docker",
            "exec",
            ambox.container_name,
            "/command/s6-setuidgid",
            "archivematica",
            "/usr/bin/test",
            "-r",
            current_full_path,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"Stored {package_type} is not readable at {current_full_path}: {result.stderr}"
    )


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


def upload_transfer_via_sftp(ambox: Services, transfer_name: str) -> None:
    with tempfile.TemporaryDirectory(prefix="ambox-e2e-sftp-") as temp_dir:
        private_key = Path(temp_dir) / "id_ed25519"
        shutil.copyfile(SFTP_PRIVATE_KEY, private_key)
        private_key.chmod(0o600)
        result = subprocess.run(
            [
                "sftp",
                "-b",
                "-",
                "-P",
                str(ambox.sftp_port),
                "-o",
                "BatchMode=yes",
                "-o",
                "IdentitiesOnly=yes",
                "-o",
                "StrictHostKeyChecking=yes",
                "-o",
                f"UserKnownHostsFile={SFTP_KNOWN_HOSTS}",
                "-i",
                str(private_key),
                "archivematica@localhost",
            ],
            input=f'put -r "{SAMPLE_TRANSFER}" "{transfer_name}"\n',
            check=False,
            capture_output=True,
            text=True,
        )
    assert result.returncode == 0, result.stderr


@when(
    "the bundled pictures are uploaded through SFTP and submitted with "
    "automated processing"
)
def submit_pictures(ambox: Services, verification: Verification) -> None:
    verification.transfer_name = f"ambox-e2e-{int(time.time())}-{os.getpid()}"
    transfer_path = os.getenv("AMBOX_TRANSFER_PATH")
    if transfer_path is None:
        transfer_path = f"/home/archivematica/transfers/{verification.transfer_name}"
        upload_transfer_via_sftp(ambox, verification.transfer_name)

    encoded_path = base64.b64encode(transfer_path.encode()).decode()
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


@then("the AIP and DIP are uploaded to Storage Service")
def aip_and_dip_are_uploaded(ambox: Services, verification: Verification) -> None:
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
                dip = related_dip(ambox, body)
                if dip is None or dip.get("status") != "UPLOADED":
                    time.sleep(interval)
                    continue

                assert_package_readable(ambox, body, "AIP", AIP_STORE_ROOT)
                assert_package_readable(ambox, dip, "DIP", DIP_STORE_ROOT)
                print(
                    f"aip_uuid={body['uuid']} aip_status={body['status']} "
                    f"aip_size={body.get('size')}"
                )
                print(
                    f"dip_uuid={dip['uuid']} dip_status={dip['status']} "
                    f"dip_size={dip.get('size')}"
                )
                return
        else:
            assert status in {400, 404}, body
        time.sleep(interval)

    pytest.fail(f"Timed out waiting for uploaded AIP and DIP {verification.sip_uuid}")
