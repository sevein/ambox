from __future__ import annotations

from clients import Services
from pages.dashboard import DashboardPage
from pytest_bdd import given
from pytest_bdd import then
from state import Verification


@given("the Dashboard login page is available")
def dashboard_login_is_available(
    ambox: Services,
    dashboard_page: DashboardPage,
) -> None:
    dashboard_page.login(ambox.dashboard_user, ambox.dashboard_password)


@then("the completed workflow is visible in Dashboard")
def completed_workflow_is_visible(
    dashboard_page: DashboardPage,
    verification: Verification,
) -> None:
    dashboard_page.assert_transfer(verification.transfer_uuid)
    dashboard_page.assert_ingest(verification.sip_uuid)
