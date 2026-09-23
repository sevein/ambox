from __future__ import annotations

import re

from playwright.sync_api import Page
from playwright.sync_api import expect


class StoragePage:
    def __init__(self, page: Page, base_url: str) -> None:
        self.page = page
        self.base_url = base_url.rstrip("/")

    def login(self, username: str, password: str) -> None:
        self.page.goto(f"{self.base_url}/login/", wait_until="domcontentloaded")
        self.page.get_by_label("Username").fill(username)
        self.page.get_by_label("Password").fill(password)
        self.page.get_by_role("button", name="Log in").click()
        expect(self.page.get_by_role("button", name="Log out")).to_be_visible()

    def open_list(self, resource: str) -> None:
        self.page.goto(f"{self.base_url}/{resource}/", wait_until="domcontentloaded")
        expect(
            self.page.get_by_role("heading", name=f"All {resource.title()}", exact=True)
        ).to_be_visible()

    def assert_table_record(self, uuid: str) -> None:
        # Inspect rendered rows, not the JSON payload embedded in the page.
        table = self.page.get_by_role("table")
        expect(
            table.get_by_role("columnheader", name="UUID", exact=True)
        ).to_be_visible()
        headers = [
            text.strip()
            for text in table.get_by_role("columnheader").all_text_contents()
        ]
        uuid_column = headers.index("UUID") + 1
        self.page.get_by_role("searchbox", name="Search:").fill(uuid)
        uuid_cell = self.page.locator(f"td:nth-child({uuid_column})").filter(
            has_text=re.compile(rf"^\s*{re.escape(uuid)}\s*$")
        )
        expect(self.page.get_by_role("row").filter(has=uuid_cell)).to_be_visible()

    def assert_space(self, uuid: str) -> None:
        expect(self.page.locator(f'a[href="/spaces/{uuid}/"]')).to_be_visible()
