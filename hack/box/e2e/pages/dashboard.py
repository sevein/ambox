from __future__ import annotations

import re

from playwright.sync_api import Page
from playwright.sync_api import expect


class DashboardPage:
    def __init__(self, page: Page, base_url: str) -> None:
        self.page = page
        self.base_url = base_url.rstrip("/")

    def login(self, username: str, password: str) -> None:
        self.page.goto(self.base_url, wait_until="domcontentloaded")
        expect(self.page).to_have_title(re.compile(r"Archivematica Dashboard"))
        expect(self.page.locator("#login")).to_be_visible()
        self.page.get_by_label("Username").fill(username)
        self.page.get_by_label("Password").fill(password)
        self.page.get_by_role("button", name="Log in").click()
        expect(self.page.locator(".nav-transfer")).to_be_visible()
        expect(self.page.locator(".nav-ingest")).to_be_visible()

    def assert_transfer(self, transfer_uuid: str) -> None:
        self.page.goto(
            f"{self.base_url}/transfer/{transfer_uuid}/",
            wait_until="domcontentloaded",
        )
        expect(
            self.page.get_by_role("heading", name=re.compile(r"^Transfer"))
        ).to_be_visible()
        expect(self.page.locator(".content")).to_contain_text(transfer_uuid)

        self.page.goto(
            f"{self.base_url}/transfer/{transfer_uuid}/microservices/",
            wait_until="domcontentloaded",
        )
        scan = self.page.locator("li").filter(
            has_text="Scan for viruses in directories"
        )
        expect(scan.first).to_contain_text("Completed successfully")

    def assert_ingest(self, sip_uuid: str) -> None:
        self.page.goto(
            f"{self.base_url}/ingest/{sip_uuid}/",
            wait_until="domcontentloaded",
        )
        expect(
            self.page.get_by_role(
                "heading", name=re.compile(r"^Submission Information Package")
            )
        ).to_be_visible()
        expect(self.page.locator(".content")).to_contain_text(sip_uuid)

        self.page.goto(
            f"{self.base_url}/ingest/{sip_uuid}/microservices/",
            wait_until="domcontentloaded",
        )
        store_aip = self.page.locator("li").filter(has_text="Store the AIP")
        expect(store_aip.first).to_contain_text("Completed successfully")
