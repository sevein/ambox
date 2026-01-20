#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.10"
# dependencies = ["PyYAML", "jsonschema"]
# ///
from __future__ import annotations

import argparse
import base64
import ast
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
import xml.etree.ElementTree as ET

import yaml
from jsonschema import Draft202012Validator


DEFAULT_CONFIG_PATH = "/etc/ambox/config.yaml"
DEFAULT_OUTPUT_DIR = (
    "/var/archivematica/sharedDirectory/sharedMicroServiceTasksConfigs/"
    "processingMCPConfigs"
)
DEFAULT_WORKFLOW_PATHS = ("/src/src/archivematica/MCPServer/assets/workflow.json",)
DEFAULT_SCHEMA_PATH = Path(__file__).with_name("schema.json")


@dataclass(frozen=True)
class FieldSpec:
    name: str
    kind: str
    link_ids: tuple[str, ...]
    value_labels: dict[Any, tuple[str, ...]] | None = None


FIELD_SPECS: dict[str, FieldSpec] = {
    "virus_scanning": FieldSpec(
        name="virus_scanning",
        kind="chain",
        link_ids=(
            "856d2d65-cd25-49fa-8da9-cabb78292894",
            "1dad74a2-95df-4825-bbba-dca8b91d2371",
            "7e81f94e-6441-4430-a12d-76df09181b66",
            "390d6507-5029-4dae-bcd4-ce7178c9b560",
            "97a5ddc0-d4e0-43ac-a571-9722405a0a9b",
        ),
        value_labels={
            True: ("Yes",),
            False: ("No",),
        },
    ),
    "assign_uuids_to_directories": FieldSpec(
        name="assign_uuids_to_directories",
        kind="replacement",
        link_ids=("bd899573-694e-4d33-8c9b-df0af802437d",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "generate_transfer_structure": FieldSpec(
        name="generate_transfer_structure",
        kind="chain",
        link_ids=("56eebd45-5600-4768-a8c2-ec0114555a3d",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "select_format_id_tool_transfer": FieldSpec(
        name="select_format_id_tool_transfer",
        kind="replacement",
        link_ids=("f09847c2-ee51-429a-9478-a860477f6b8d",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "extract_packages": FieldSpec(
        name="extract_packages",
        kind="chain",
        link_ids=("dec97e3c-5598-4b99-b26e-f87a435a6b7f",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "delete_packages": FieldSpec(
        name="delete_packages",
        kind="replacement",
        link_ids=("f19926dd-8fb5-4c79-8ade-c83f61f55b40",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "policy_checks_originals": FieldSpec(
        name="policy_checks_originals",
        kind="chain",
        link_ids=("70fc7040-d4fb-4d19-a0e6-792387ca1006",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "examine_contents": FieldSpec(
        name="examine_contents",
        kind="chain",
        link_ids=("accea2bf-ba74-4a3a-bb97-614775c74459",),
        value_labels={True: ("Examine contents",), False: ("Skip examine contents",)},
    ),
    "create_sip": FieldSpec(
        name="create_sip",
        kind="chain",
        link_ids=("bb194013-597c-4e4a-8493-b36d190f8717",),
        value_labels={
            True: (
                "Create SIP from Transfer",
                "Create SIP from transfer objects",
                "Create SIPs from TRIM transfer containers",
            ),
            False: ("Reject transfer",),
        },
    ),
    "select_format_id_tool_ingest": FieldSpec(
        name="select_format_id_tool_ingest",
        kind="replacement",
        link_ids=("7a024896-c4f7-4808-a240-44c87c762bc5",),
        value_labels={True: ("Yes",), False: ("No, use existing data",)},
    ),
    "normalize": FieldSpec(
        name="normalize",
        kind="chain",
        link_ids=("cb8e5706-e73f-472f-ad9b-d1236af8095f",),
        value_labels={
            "preservation_access": ("Normalize for preservation and access",),
            "preservation": ("Normalize for preservation",),
            "access": ("Normalize for access",),
            "service_access": ("Normalize service files for access",),
            "manual": ("Normalize manually",),
            "do_not_normalize": ("Do not normalize",),
        },
    ),
    "normalize_transfer": FieldSpec(
        name="normalize_transfer",
        kind="chain",
        link_ids=("de909a42-c5b5-46e1-9985-c031b50e9d30",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "normalize_thumbnail_mode": FieldSpec(
        name="normalize_thumbnail_mode",
        kind="replacement",
        link_ids=("498f7a6d-1b8c-431a-aa5d-83f14f3c5e65",),
        value_labels={
            "yes": ("Yes",),
            "yes_no_icons": ("Yes, without default icons",),
            "no": ("No",),
        },
    ),
    "policy_checks_preservation_derivatives": FieldSpec(
        name="policy_checks_preservation_derivatives",
        kind="chain",
        link_ids=("153c5f41-3cfb-47ba-9150-2dd44ebc27df",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "policy_checks_access_derivatives": FieldSpec(
        name="policy_checks_access_derivatives",
        kind="chain",
        link_ids=("8ce07e94-6130-4987-96f0-2399ad45c5c2",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "bind_pids": FieldSpec(
        name="bind_pids",
        kind="chain",
        link_ids=("a2ba5278-459a-4638-92d9-38eb1588717d",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "normative_structmap": FieldSpec(
        name="normative_structmap",
        kind="chain",
        link_ids=("d0dfa5fc-e3c2-4638-9eda-f96eea1070e0",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "reminder": FieldSpec(
        name="reminder",
        kind="chain",
        link_ids=("eeb23509-57e2-4529-8857-9d62525db048",),
        value_labels={"continue": ("Continue",)},
    ),
    "transcribe_file": FieldSpec(
        name="transcribe_file",
        kind="chain",
        link_ids=("82ee9ad2-2c74-4c7c-853e-e4eaf68fc8b6",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "select_format_id_tool_submissiondocs": FieldSpec(
        name="select_format_id_tool_submissiondocs",
        kind="replacement",
        link_ids=("087d27be-c719-47d8-9bbb-9a7d8b609c44",),
        value_labels={True: ("Yes",), False: ("No",)},
    ),
    "compression_algo": FieldSpec(
        name="compression_algo",
        kind="replacement",
        link_ids=("01d64f58-8295-4b7b-9cab-8f1b153a504f",),
        value_labels={
            "7z_bzip2": ("7z using bzip2",),
            "7z_lzma": ("7z using lzma",),
            "7z_none": ("7z without compression",),
            "tar_gzip": ("Gzipped tar",),
            "pbzip2": ("Parallel bzip2",),
            "uncompressed": ("Uncompressed",),
        },
    ),
    "compression_level": FieldSpec(
        name="compression_level",
        kind="replacement",
        link_ids=("01c651cb-c174-4ba4-b985-1d87a44d6754",),
        value_labels={
            1: ("1 - fastest compression",),
            3: ("3 - fast compression",),
            5: ("5 - normal compression",),
            7: ("7 - maximum compression",),
            9: ("9 - ultra compression",),
        },
    ),
    "store_aip": FieldSpec(
        name="store_aip",
        kind="chain",
        link_ids=("2d32235c-02d4-4686-88a6-96f4d6c7b1c3",),
        value_labels={True: ("Yes",), False: ("Reject AIP",)},
    ),
    "store_aip_location": FieldSpec(
        name="store_aip_location",
        kind="location",
        link_ids=("b320ce81-9982-408a-9502-097d0daa48fa",),
    ),
    "upload_dip": FieldSpec(
        name="upload_dip",
        kind="chain",
        link_ids=("92879a29-45bf-4f0b-ac43-e64474f0f2f9",),
        value_labels={
            "atom": ("Upload DIP to AtoM",),
            "archivesspace": ("Upload DIP to ArchivesSpace",),
            "contentdm": ("Upload DIP to CONTENTdm",),
            "do_not_upload": ("Do not upload DIP",),
        },
    ),
    "store_dip": FieldSpec(
        name="store_dip",
        kind="chain",
        link_ids=("5e58066d-e113-4383-b20b-f301ed4d751c",),
        value_labels={True: ("Store DIP",), False: ("Reject DIP",)},
    ),
    "store_dip_location": FieldSpec(
        name="store_dip_location",
        kind="location",
        link_ids=("cd844b6e-ab3c-4bc6-b34f-7103f88715de",),
    ),
}


def _load_yaml(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ValueError("config root must be a mapping")
    return data


def _load_workflow(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def _find_repo_candidate(relative_path: str) -> Path | None:
    resolved = Path(__file__).resolve()
    for parent in resolved.parents:
        candidate = parent / relative_path
        if candidate.is_file():
            return candidate
    return None


def _find_workflow_path() -> Path:
    for candidate in DEFAULT_WORKFLOW_PATHS:
        path = Path(candidate)
        if path.is_file():
            return path
    local_candidate = _find_repo_candidate(
        "src/archivematica/MCPServer/assets/workflow.json"
    )
    if local_candidate:
        return local_candidate
    raise FileNotFoundError("workflow.json not found")


def _load_processing_constants() -> dict[str, str]:
    local_candidate = _find_repo_candidate(
        "src/archivematica/archivematicaCommon/processing.py"
    )
    if not local_candidate:
        raise FileNotFoundError("processing.py not found")

    text = local_candidate.read_text(encoding="utf-8")
    tree = ast.parse(text, filename=str(local_candidate))
    values: dict[str, str] = {}
    targets = {
        "DEFAULT_PROCESSING_CONFIG": "default",
        "AUTOMATED_PROCESSING_CONFIG": "automated",
    }
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        if len(node.targets) != 1 or not isinstance(node.targets[0], ast.Name):
            continue
        name = node.targets[0].id
        if name not in targets:
            continue
        if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            values[targets[name]] = node.value.value
            continue
        raise ValueError(f"{name} is not a literal string in processing.py")

    missing = [key for key in targets.values() if key not in values]
    if missing:
        raise ValueError(f"missing processing constants: {', '.join(missing)}")
    return values


def _load_schema(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(f"schema not found at {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _validate_schema(schema: dict[str, Any], data: dict[str, Any]) -> None:
    Draft202012Validator(schema).validate(data)


def _parse_base_config(xml_text: str | None) -> ET.ElementTree:
    if xml_text:
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
        return ET.ElementTree(ET.fromstring(xml_text, parser=parser))
    root = ET.Element("processingMCP")
    ET.SubElement(root, "preconfiguredChoices")
    return ET.ElementTree(root)


def _get_choices_root(tree: ET.ElementTree) -> ET.Element:
    root = tree.getroot()
    choices = root.find("preconfiguredChoices")
    if choices is None:
        choices = ET.SubElement(root, "preconfiguredChoices")
    return choices


def _is_comment(element: ET.Element) -> bool:
    return element.tag is ET.Comment


def _remove_choice(choices: ET.Element, link_id: str) -> None:
    children = list(choices)
    for index, element in enumerate(children):
        if element.tag != "preconfiguredChoice":
            continue
        applies = element.find("appliesTo")
        if applies is None:
            continue
        if (applies.text or "").strip() == link_id:
            if index > 0 and _is_comment(children[index - 1]):
                choices.remove(children[index - 1])
            choices.remove(element)


def _upsert_choice(choices: ET.Element, link_id: str, value: str) -> ET.Element:
    for element in choices.findall("preconfiguredChoice"):
        applies = element.find("appliesTo")
        if applies is not None and (applies.text or "").strip() == link_id:
            target = element.find("goToChain")
            if target is None:
                target = ET.SubElement(element, "goToChain")
            target.text = value
            return element
    element = ET.Element("preconfiguredChoice")
    applies = ET.SubElement(element, "appliesTo")
    applies.text = link_id
    target = ET.SubElement(element, "goToChain")
    target.text = value
    choices.append(element)
    return element


def _find_chain_choice(
    workflow: dict[str, Any], link_id: str, label_candidates: Iterable[str]
) -> tuple[str, str] | None:
    link = workflow.get("links", {}).get(link_id)
    if not link:
        return None
    chains = workflow.get("chains", {})
    for chain_id in link.get("config", {}).get("chain_choices", []):
        chain = chains.get(chain_id, {})
        label = ((chain.get("description", {}) or {}).get("en") or "").strip()
        for candidate in label_candidates:
            if label == candidate:
                return chain_id, candidate
    return None


def _find_replacement_choice(
    workflow: dict[str, Any], link_id: str, label_candidates: Iterable[str]
) -> tuple[str, str] | None:
    link = workflow.get("links", {}).get(link_id)
    if not link:
        return None
    for item in link.get("config", {}).get("replacements", []):
        description = item.get("description", {})
        label = (description.get("en") or "").strip()
        for candidate in label_candidates:
            if label == candidate:
                return item.get("id"), candidate
    return None


def _link_prompt(workflow: dict[str, Any], link_id: str) -> str | None:
    link = workflow.get("links", {}).get(link_id)
    if not link:
        return None
    label = ((link.get("description") or {}).get("en") or "").strip()
    return label or None


def _sanitize_comment(text: str) -> str:
    return text.replace("--", "-").strip()


def _set_choice_comment(
    choices: ET.Element,
    element: ET.Element,
    comment_text: str | None,
) -> None:
    if not comment_text:
        return
    children = list(choices)
    try:
        index = children.index(element)
    except ValueError:
        return
    comment_text = f" {_sanitize_comment(comment_text)} "
    if index > 0 and _is_comment(children[index - 1]):
        children[index - 1].text = comment_text
        return
    choices.insert(index, ET.Comment(comment_text))


def _location_uri(value: str, purpose: str) -> str:
    if value == "default":
        return f"/api/v2/location/default/{purpose}/"
    if value.startswith("location:"):
        location_id = value.split("location:", 1)[1]
        return f"/api/v2/location/{location_id}/"
    raise ValueError(f"unsupported location value: {value}")


def _apply_config(
    tree: ET.ElementTree,
    workflow: dict[str, Any],
    config: dict[str, Any],
) -> None:
    choices = _get_choices_root(tree)
    for key, value in config.items():
        spec = FIELD_SPECS.get(key)
        if spec is None:
            raise ValueError(f"unknown processing config key: {key}")
        if value is None:
            for link_id in spec.link_ids:
                _remove_choice(choices, link_id)
            continue

        if spec.kind == "location":
            purpose = "AS" if key == "store_aip_location" else "DS"
            uri = _location_uri(value, purpose)
            for link_id in spec.link_ids:
                element = _upsert_choice(choices, link_id, uri)
                prompt = _link_prompt(workflow, link_id)
                comment_value = str(value)
                if prompt:
                    comment = f"{prompt} - {comment_value}"
                else:
                    comment = comment_value
                _set_choice_comment(choices, element, comment)
            continue

        if not spec.value_labels:
            raise ValueError(f"missing value labels for {key}")
        labels = spec.value_labels.get(value)
        if not labels:
            raise ValueError(f"unsupported value for {key}: {value}")

        for link_id in spec.link_ids:
            if spec.kind == "chain":
                choice = _find_chain_choice(workflow, link_id, labels)
            elif spec.kind == "replacement":
                choice = _find_replacement_choice(workflow, link_id, labels)
            else:
                raise ValueError(f"unsupported field kind: {spec.kind}")

            if not choice:
                raise ValueError(
                    f"no matching choice for {key}={value} at link {link_id}"
                )
            chain_id, label = choice
            element = _upsert_choice(choices, link_id, chain_id)
            prompt = _link_prompt(workflow, link_id)
            comment_value = label
            if prompt:
                comment = f"{prompt} - {comment_value}"
            else:
                comment = comment_value
            _set_choice_comment(choices, element, comment)


def _render_tree(tree: ET.ElementTree) -> str:
    ET.indent(tree, space="  ", level=0)
    root = tree.getroot()
    return ET.tostring(root, encoding="unicode")


def _load_source(source: dict[str, Any]) -> str:
    source_type = source.get("type")
    value = source.get("value")
    if source_type == "base64":
        return base64.b64decode(value).decode("utf-8")
    if source_type == "file":
        return Path(value).read_text(encoding="utf-8")
    raise ValueError(f"unsupported source type: {source_type}")


def _write_output(output_dir: Path, name: str, xml_text: str) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    target = output_dir / f"{name}ProcessingMCP.xml"
    target.write_text(xml_text, encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate processing configs")
    parser.add_argument("--config", default=DEFAULT_CONFIG_PATH)
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--workflow")
    parser.add_argument("--schema", default=str(DEFAULT_SCHEMA_PATH))
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.is_file():
        return 0

    data = _load_yaml(str(config_path))
    schema_path = Path(args.schema)
    schema = _load_schema(schema_path)
    _validate_schema(schema, data)
    processing = data.get("processing") or {}
    configs = processing.get("configs") or []
    if not isinstance(configs, list):
        raise ValueError("processing.configs must be a list")

    workflow_path = Path(args.workflow) if args.workflow else _find_workflow_path()
    workflow = _load_workflow(str(workflow_path))
    base_configs = _load_processing_constants()

    output_dir = Path(args.output_dir)
    for item in configs:
        if not isinstance(item, dict):
            raise ValueError("processing.configs entries must be objects")
        name = item.get("name")
        if not name:
            raise ValueError("processing.configs entry missing name")

        if "source" in item:
            xml_text = _load_source(item["source"])
            _write_output(output_dir, name, xml_text)
            continue

        if "config" in item:
            base = item.get("extends")
            xml_text = base_configs.get(base) if base else None
            tree = _parse_base_config(xml_text)
            config = item.get("config") or {}
            if not isinstance(config, dict):
                raise ValueError(f"config for {name} must be an object")
            _apply_config(tree, workflow, config)
            _write_output(output_dir, name, _render_tree(tree))
            continue

        raise ValueError(f"processing config entry '{name}' missing source/config")

    return 0


if __name__ == "__main__":
    sys.exit(main())
