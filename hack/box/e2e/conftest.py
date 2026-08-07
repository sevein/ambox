from __future__ import annotations

import os
from pathlib import Path

import pytest
from clients import API
from clients import Services
from pages.dashboard import DashboardPage
from runtime import CONTAINER_NAME
from runtime import E2E_ROOT
from runtime import assert_storage_mounts
from runtime import capture_failure_artifacts
from runtime import clear_failure_artifacts
from runtime import start_ambox
from runtime import stop_ambox
from runtime import wait_for_dashboard
from runtime import wait_for_sftp
from state import Verification

pytest_plugins = ("steps.archivematica", "steps.dashboard")


def pytest_configure(config: pytest.Config) -> None:
    config._ambox_e2e_failed = False


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item: pytest.Item, call: pytest.CallInfo[object]):
    outcome = yield
    report = outcome.get_result()
    if report.failed:
        item.config._ambox_e2e_failed = True


@pytest.fixture
def verification() -> Verification:
    return Verification()


@pytest.fixture(scope="session")
def ambox(pytestconfig: pytest.Config) -> Services:
    dashboard_url = os.getenv("AMBOX_DASHBOARD_URL", "http://127.0.0.1:64080")
    storage_url = os.getenv("AMBOX_STORAGE_URL", "http://127.0.0.1:64081")
    sftp_port = int(os.getenv("AMBOX_SFTP_PORT", "64022"))
    api_user = os.getenv("AMBOX_API_USER", "test")
    api_key = os.getenv("AMBOX_API_KEY", "test")
    authorization = f"ApiKey {api_user}:{api_key}"
    output_root = Path(os.getenv("AMBOX_E2E_OUTPUT", E2E_ROOT / "output"))
    services = Services(
        dashboard=API(dashboard_url.rstrip("/"), authorization),
        storage=API(storage_url.rstrip("/"), authorization),
        dashboard_url=dashboard_url,
        sftp_port=sftp_port,
        dashboard_user=os.getenv("AMBOX_DASHBOARD_USER", "test"),
        dashboard_password=os.getenv("AMBOX_DASHBOARD_PASSWORD", "test"),
        container_name=CONTAINER_NAME,
    )

    clear_failure_artifacts(output_root)
    process = start_ambox()
    try:
        wait_for_dashboard(process, dashboard_url)
        wait_for_sftp(process, sftp_port)
        assert_storage_mounts()
        yield services
    finally:
        if pytestconfig._ambox_e2e_failed:
            capture_failure_artifacts(services, output_root)
        stop_ambox(process)


@pytest.fixture
def dashboard_page(page, ambox: Services) -> DashboardPage:
    return DashboardPage(page, ambox.dashboard_url)
