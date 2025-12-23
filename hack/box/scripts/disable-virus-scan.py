#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# ///
import os
import sys
import json
import xml.etree.ElementTree as ET

CONFIGS = os.getenv("AM_PROCESSING_CONFIGS", "default automated").split()
SHARED_DIR = os.getenv("AM_SHARED_DIRECTORY", "/var/archivematica/sharedDirectory")
CONFIG_DIR = os.path.join(
    SHARED_DIR, "sharedMicroServiceTasksConfigs", "processingMCPConfigs"
)
WORKFLOW_PATH = os.getenv(
    "AM_WORKFLOW_PATH", "/src/src/archivematica/MCPServer/assets/workflow.json"
)

VIRUS_LINK_IDS = [
    "856d2d65-cd25-49fa-8da9-cabb78292894",
    "1dad74a2-95df-4825-bbba-dca8b91d2371",
    "7e81f94e-6441-4430-a12d-76df09181b66",
    "390d6507-5029-4dae-bcd4-ce7178c9b560",
    "97a5ddc0-d4e0-43ac-a571-9722405a0a9b",
]


def log(message: str) -> None:
    print(f"processing-config: {message}", flush=True)


def _load_no_chain_ids() -> dict:
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as handle:
        workflow = json.load(handle)

    links = workflow.get("links", {})
    chains = workflow.get("chains", {})
    mapping = {}

    for link_id in VIRUS_LINK_IDS:
        link = links.get(link_id)
        if not link:
            continue
        for chain_id in link.get("config", {}).get("chain_choices", []):
            chain = chains.get(chain_id, {})
            description = (chain.get("description", {}) or {}).get("en")
            if description == "No":
                mapping[link_id] = chain_id
                break

    return mapping


def _update_config(path: str, no_chain_ids: dict) -> None:
    tree = ET.parse(path)
    root = tree.getroot()

    updated = False
    for choice in root.findall(".//preconfiguredChoice"):
        applies = choice.find("appliesTo")
        go_to = choice.find("goToChain")
        if applies is None or go_to is None:
            continue
        link_id = (applies.text or "").strip()
        no_chain = no_chain_ids.get(link_id)
        if not no_chain:
            continue
        if (go_to.text or "").strip() == no_chain:
            continue
        go_to.text = no_chain
        updated = True

    if updated:
        tree.write(path, encoding="utf-8", xml_declaration=True)


def _verify_config(path: str, no_chain_ids: dict) -> None:
    tree = ET.parse(path)
    root = tree.getroot()
    for link_id, no_chain in no_chain_ids.items():
        for choice in root.findall(".//preconfiguredChoice"):
            applies = choice.find("appliesTo")
            go_to = choice.find("goToChain")
            if applies is None or go_to is None:
                continue
            if (applies.text or "").strip() != link_id:
                continue
            if (go_to.text or "").strip() != no_chain:
                raise RuntimeError(
                    f"{os.path.basename(path)}: {link_id} not set to 'No'"
                )


def main() -> int:
    if not CONFIGS:
        log("no configs provided; skipping.")
        return 0

    if not os.path.isfile(WORKFLOW_PATH):
        raise RuntimeError(f"workflow.json not found at {WORKFLOW_PATH}")

    no_chain_ids = _load_no_chain_ids()
    if not no_chain_ids:
        raise RuntimeError("failed to resolve 'No' chain IDs from workflow")

    for name in CONFIGS:
        path = os.path.join(CONFIG_DIR, f"{name}ProcessingMCP.xml")
        if not os.path.isfile(path):
            raise RuntimeError(f"missing processing config: {path}")
        log(f"updating {path}...")
        _update_config(path, no_chain_ids)
        _verify_config(path, no_chain_ids)

    log("virus scanning disabled.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        log(f"failed: {exc}")
        raise
