from __future__ import annotations

import http.client
import os
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

from clients import Services

E2E_ROOT = Path(__file__).resolve().parent
BOX_ROOT = E2E_ROOT.parent
CONTAINER_NAME = "ambox-test"


def clear_failure_artifacts(output_root: Path) -> None:
    for path in (
        output_root / "api" / "dashboard.json",
        output_root / "api" / "storage.json",
        output_root / "docker" / "ambox.log",
    ):
        path.unlink(missing_ok=True)


def fetch_text(url: str) -> tuple[int, str]:
    request = urllib.request.Request(url, method="GET")
    try:
        response = urllib.request.urlopen(request, timeout=10)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, response.read().decode("utf-8", errors="replace")


def container_exists() -> bool:
    result = subprocess.run(
        [
            "docker",
            "ps",
            "--all",
            "--filter",
            f"name=^/{CONTAINER_NAME}$",
            "--format",
            "{{.Names}}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return CONTAINER_NAME in result.stdout.splitlines()


def start_ambox() -> subprocess.Popen[bytes]:
    if container_exists():
        raise RuntimeError(
            f"Container {CONTAINER_NAME!r} already exists; stop it before verifying"
        )

    target = "run-image" if os.getenv("AMBOX_SKIP_BUILD", "0") == "1" else "run"
    print(f"Starting ambox with make target {target}", flush=True)
    return subprocess.Popen(["make", "-C", str(BOX_ROOT), target])


def wait_for_dashboard(process: subprocess.Popen[bytes], url: str) -> None:
    deadline = time.monotonic() + 300
    last_error = "Dashboard did not respond"
    while time.monotonic() < deadline:
        return_code = process.poll()
        if return_code is not None:
            raise RuntimeError(f"ambox exited before readiness (status {return_code})")
        try:
            status, _ = fetch_text(url)
        except (http.client.HTTPException, OSError, urllib.error.URLError) as error:
            last_error = str(error)
        else:
            if status == 200:
                return
            last_error = f"HTTP {status}"
        time.sleep(5)
    raise RuntimeError(f"Timed out waiting for {url}: {last_error}")


def capture_failure_artifacts(services: Services, output_root: Path) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    services.dashboard.write_history(output_root / "api" / "dashboard.json")
    services.storage.write_history(output_root / "api" / "storage.json")

    if not container_exists():
        return
    result = subprocess.run(
        ["docker", "logs", services.container_name],
        check=False,
        capture_output=True,
        text=True,
    )
    log = result.stdout
    if result.stderr:
        log += f"\n--- stderr ---\n{result.stderr}"
    docker_log = output_root / "docker" / "ambox.log"
    docker_log.parent.mkdir(parents=True, exist_ok=True)
    docker_log.write_text(log, encoding="utf-8")


def stop_ambox(process: subprocess.Popen[bytes]) -> None:
    if container_exists():
        subprocess.run(
            ["docker", "stop", CONTAINER_NAME],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    try:
        process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
