#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.10"
# dependencies = ["PyYAML"]
# ///
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import yaml


def load_yaml(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
    except FileNotFoundError:
        return {}
    except Exception as exc:  # pragma: no cover - surfaced to caller
        print(f"Failed to read config {path}: {exc}", file=sys.stderr)
        raise
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"Config {path} must be a mapping at the top level")
    return data


def resolve_host_key(config: dict[str, Any]) -> str | None:
    sftpgo = config.get("sftpgo")
    if sftpgo is None:
        return None
    if not isinstance(sftpgo, dict):
        raise ValueError("sftpgo config must be a mapping")
    host_key = sftpgo.get("host_key")
    if host_key is None:
        return None
    if not isinstance(host_key, str):
        raise ValueError("sftpgo.host_key must be a string")
    host_key = host_key.strip()
    return host_key or None


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError as exc:
        print(f"Base SFTPGo config not found: {path}", file=sys.stderr)
        raise exc
    if not isinstance(data, dict):
        raise ValueError(f"SFTPGo config {path} must be a JSON object")
    return data


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=False)
        handle.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, help="Path to ambox config.yaml")
    parser.add_argument(
        "--base-config",
        required=True,
        help="Path to the base sftpgo.json to read",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Path to write the rendered sftpgo.json",
    )
    parser.add_argument(
        "--config-dir",
        default="/var/lib/sftpgo",
        help="SFTPGo config dir for resolving relative host key paths",
    )
    args = parser.parse_args()

    config_path = Path(args.config)
    base_config_path = Path(args.base_config)
    output_path = Path(args.output)
    config_dir = Path(args.config_dir)

    try:
        config = load_yaml(config_path)
        host_key = resolve_host_key(config)
        sftpgo_config = load_json(base_config_path)
    except Exception:
        return 1

    if host_key:
        host_key_path = Path(host_key)
        if not host_key_path.is_absolute():
            host_key_path = config_dir / host_key_path
        if not host_key_path.is_file():
            print(
                f"Configured sftpgo.host_key does not exist: {host_key_path}",
                file=sys.stderr,
            )
            return 1
        sftpd = sftpgo_config.get("sftpd")
        if sftpd is None:
            sftpd = {}
            sftpgo_config["sftpd"] = sftpd
        if not isinstance(sftpd, dict):
            print("sftpd config must be a JSON object", file=sys.stderr)
            return 1
        sftpd["host_keys"] = [str(host_key_path)]

    write_json(output_path, sftpgo_config)
    return 0


if __name__ == "__main__":
    sys.exit(main())
