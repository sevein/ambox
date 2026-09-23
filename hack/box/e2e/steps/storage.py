from __future__ import annotations

from typing import Any

from clients import Services
from pages.storage import StoragePage
from pytest_bdd import given
from pytest_bdd import then
from state import Verification

from steps.archivematica import require_uuid


def list_records(ambox: Services, resource: str) -> list[dict[str, Any]]:
    path = f"/api/v2/{resource}/"
    records = []
    while path:
        status, body = ambox.storage.request(path)
        assert status == 200, body
        assert isinstance(body, dict), body
        assert isinstance(body.get("objects"), list), body
        records.extend(body["objects"])
        path = body["meta"]["next"]
    assert len(records) == body["meta"]["total_count"], body
    return records


@given("Storage Service is connected to the advertised Archivematica pipeline")
@then("Storage Service is connected to the advertised Archivematica pipeline")
def storage_is_connected(ambox: Services, verification: Verification) -> None:
    status, body = ambox.dashboard.request("/api/transfer/unapproved/")
    assert status == 200, body
    verification.pipeline_uuid = require_uuid(
        ambox.dashboard.history[-1].headers.get("x-archivematica-id"), "pipeline"
    )
    pipelines = list_records(ambox, "pipeline")
    matches = [p for p in pipelines if p["uuid"] == verification.pipeline_uuid]
    assert len(matches) == 1, (verification.pipeline_uuid, pipelines)
    pipeline_uri = matches[0]["resource_uri"]

    verification.spaces = list_records(ambox, "space")
    verification.locations = list_records(ambox, "location")
    assert verification.spaces, "Expected bootstrapped spaces"
    assert verification.locations, "Expected bootstrapped locations"
    space_uris = {space["resource_uri"] for space in verification.spaces}
    for location in verification.locations:
        assert location["space"] in space_uris, location
    purposes = {
        location["purpose"]
        for location in verification.locations
        if location["enabled"] and pipeline_uri in location["pipeline"]
    }
    assert {"TS", "AS", "DS", "BL", "CP"} <= purposes, purposes
    # An empty package list is valid before any transfers have been submitted.
    list_records(ambox, "file")


@then("the storage configuration is visible in Storage Service")
def storage_configuration_is_visible(
    storage_page: StoragePage, verification: Verification
) -> None:
    storage_page.open_list("pipelines")
    storage_page.assert_table_record(verification.pipeline_uuid)
    storage_page.open_list("spaces")
    for space in verification.spaces:
        storage_page.assert_space(space["uuid"])
    storage_page.open_list("locations")
    for location in verification.locations:
        storage_page.assert_table_record(location["uuid"])


@then("the AIP and DIP are listed by the Storage Service API")
def packages_are_listed(ambox: Services, verification: Verification) -> None:
    packages = {package["uuid"]: package for package in list_records(ambox, "file")}
    locations = {loc["resource_uri"]: loc for loc in verification.locations}
    assert len(verification.packages) == 2, verification.packages
    for expected in verification.packages:
        package = packages[expected["uuid"]]
        assert package["package_type"] == expected["package_type"], package
        assert package["status"] == "UPLOADED", package
        assert package["origin_pipeline"] == (
            f"/api/v2/pipeline/{verification.pipeline_uuid}/"
        ), package
        location = locations[package["current_location"]]
        assert package["origin_pipeline"] in location["pipeline"], location
        assert (
            location["purpose"] == {"AIP": "AS", "DIP": "DS"}[package["package_type"]]
        ), location


@then("the AIP and DIP are visible in Storage Service")
def packages_are_visible(storage_page: StoragePage, verification: Verification) -> None:
    storage_page.open_list("packages")
    for package in verification.packages:
        storage_page.assert_table_record(package["uuid"])
