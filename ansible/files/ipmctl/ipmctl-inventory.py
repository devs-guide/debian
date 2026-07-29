#!/usr/bin/env python3
"""Collect and normalize read-only ipmctl and ndctl observations."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
from pathlib import Path
from typing import Any


COMMANDS = {
    "version": ["ipmctl", "version"],
    "dimms": ["ipmctl", "show", "-a", "-dimm"],
    "topology": ["ipmctl", "show", "-a", "-topology"],
    "memory_resources": ["ipmctl", "show", "-u", "B", "-memoryresources"],
    "regions": ["ipmctl", "show", "-a", "-region"],
    "sensors": ["ipmctl", "show", "-sensor"],
    "capabilities": ["ipmctl", "show", "-a", "-system", "-capabilities"],
    "goal": ["ipmctl", "show", "-a", "-goal"],
    "ndctl_dimms": ["ndctl", "list", "-D"],
    "ndctl_regions": ["ndctl", "list", "-R"],
    "ndctl_namespaces": ["ndctl", "list", "-N"],
}


def safe_name(value: str) -> str:
    return value.replace("_", "-")


def fixture_path(
    fixture_dir: Path | None,
    fixture_base_dir: Path | None,
    filename: str,
) -> Path | None:
    for directory in (fixture_dir, fixture_base_dir):
        if directory is not None and (directory / filename).exists():
            return directory / filename
    return None


def execute(
    argv: list[str],
    fixture_dir: Path | None,
    fixture_base_dir: Path | None,
    log_dir: Path | None,
    name: str,
) -> dict[str, Any]:
    if fixture_dir:
        stdout_path = fixture_path(
            fixture_dir, fixture_base_dir, f"{safe_name(name)}.txt"
        )
        rc_path = fixture_path(
            fixture_dir, fixture_base_dir, f"{safe_name(name)}.rc"
        )
        stdout = stdout_path.read_text(encoding="utf-8") if stdout_path else ""
        rc = int(rc_path.read_text(encoding="utf-8").strip()) if rc_path else 127
        stderr = ""
    else:
        try:
            result = subprocess.run(argv, check=False, capture_output=True, text=True)
            stdout, stderr, rc = result.stdout, result.stderr, result.returncode
        except FileNotFoundError as error:
            stdout, stderr, rc = "", str(error), 127
    if log_dir:
        log_dir.mkdir(parents=True, exist_ok=True)
        (log_dir / f"{safe_name(name)}.txt").write_text(stdout, encoding="utf-8")
        (log_dir / f"{safe_name(name)}.stderr.txt").write_text(stderr, encoding="utf-8")
        (log_dir / f"{safe_name(name)}.rc").write_text(f"{rc}\n", encoding="utf-8")
    return {"argv": argv, "rc": rc, "stdout": stdout, "stderr": stderr}


def parse_json_list(text: str) -> list[Any]:
    try:
        value = json.loads(text or "[]")
    except json.JSONDecodeError:
        return []
    return value if isinstance(value, list) else [value]


def pipe_table_records(text: str) -> list[dict[str, str]]:
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if "|" not in line:
            continue
        header = [column.strip() for column in line.strip().strip("|").split("|")]
        if len(header) < 2 or len(set(header)) != len(header):
            continue
        separator_index = index + 1
        while separator_index < len(lines) and not lines[separator_index].strip():
            separator_index += 1
        if separator_index >= len(lines) or not re.fullmatch(
            r"[\s=+-]+", lines[separator_index]
        ):
            continue
        records: list[dict[str, str]] = []
        for row_line in lines[separator_index + 1 :]:
            if not row_line.strip():
                break
            if "|" not in row_line:
                continue
            row = [
                column.strip()
                for column in row_line.strip().strip("|").split("|")
            ]
            if len(row) != len(header):
                continue
            records.append(dict(zip(header, row)))
        if records:
            return records
    return []


def values_for(text: str, label: str) -> list[str]:
    pattern = re.compile(
        rf"(?im)^\s*(?:---)?{re.escape(label)}\s*(?:=|:)\s*(.*?)"
        rf"(?:---)?\s*$"
    )
    values = [match.group(1).strip(" |-") for match in pattern.finditer(text)]
    values.extend(
        record[label].strip()
        for record in pipe_table_records(text)
        if label in record and record[label].strip()
    )
    return values


def first_value(text: str, label: str) -> str:
    values = values_for(text, label)
    return values[0] if values else ""


def capacity_bytes(text: str, label: str) -> int:
    value = first_value(text, label)
    if not value:
        match = re.search(
            rf"(?im)^\s*{re.escape(label)}\s*\|\s*(.*?)\s*$", text
        )
        value = match.group(1).strip(" |") if match else ""
    match = re.search(r"([0-9][0-9,]*)", value)
    return int(match.group(1).replace(",", "")) if match else 0


def contains_all_state(text: str, label: str, accepted: set[str]) -> bool:
    values = [value.lower() for value in values_for(text, label)]
    return bool(values) and all(value in accepted for value in values)


def normalized_words(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def security_state_safe(value: str) -> bool:
    tokens = set(re.findall(r"[a-z]+", value.lower()))
    return "locked" not in tokens and bool(tokens & {"disabled", "unlocked"})


def normalize(observations: dict[str, dict[str, Any]], log_dir: Path | None) -> dict[str, Any]:
    dimms = observations["dimms"]["stdout"]
    topology = observations["topology"]["stdout"]
    memory = observations["memory_resources"]["stdout"]
    region_output = observations["regions"]["stdout"]
    capabilities = observations["capabilities"]["stdout"]
    goal = observations["goal"]["stdout"]
    namespaces = parse_json_list(observations["ndctl_namespaces"]["stdout"])
    regions = parse_json_list(observations["ndctl_regions"]["stdout"])
    ndctl_dimms = parse_json_list(observations["ndctl_dimms"]["stdout"])

    volatile_pmem = capacity_bytes(memory, "Volatile PMem module Capacity")
    app_direct = capacity_bytes(memory, "AppDirect PMem module Capacity")
    cache_ddr = capacity_bytes(memory, "Cache DDR Capacity")
    current_volatile_mode = first_value(capabilities, "CurrentVolatileMode")
    current_volatile_mode_normalized = normalized_words(current_volatile_mode)
    region_types = values_for(region_output, "PersistentMemoryType")
    normalized_region_types = {
        normalized_words(value) for value in region_types if value
    }
    if current_volatile_mode_normalized in {"2lm", "memorymode"} and volatile_pmem > 0:
        current_mode = "mixed" if app_direct > 0 else "memory-mode"
    elif app_direct > 0:
        if normalized_region_types == {"appdirect"}:
            current_mode = "app-direct"
        elif normalized_region_types == {"appdirectnotinterleaved"}:
            current_mode = "app-direct-not-interleaved"
        else:
            current_mode = "app-direct-unknown"
    else:
        current_mode = "unknown"

    pending_goal = bool(re.search(r"(?im)^\s*Status\s*(?:=|:|\|)\s*New\b", goal))
    dimm_ids = values_for(dimms, "DimmID")
    topology_records = pipe_table_records(topology)
    topology_dimm_ids = values_for(topology, "DimmID")
    topology_socket_values = [
        record.get("SocketID", "")
        for record in topology_records
        if record.get("DimmID", "") in dimm_ids
    ] or values_for(topology, "SocketID")
    sockets = sorted(
        {
            int(value, 0)
            for value in topology_socket_values
            if re.fullmatch(r"(?:0x[0-9a-fA-F]+|[0-9]+)", value)
        }
    )
    topology_verified = (
        bool(dimm_ids)
        and bool(sockets)
        and set(dimm_ids).issubset(set(topology_dimm_ids))
    )
    version_text = observations["version"]["stdout"].strip()
    modes_supported = (
        first_value(capabilities, "ModesSupported")
        or first_value(dimms, "ModesSupported")
    )
    normalized_modes = normalized_words(modes_supported)
    security_values = values_for(dimms, "SecurityState") or values_for(dimms, "LockState")
    security_safe = bool(security_values) and all(
        security_state_safe(value) for value in security_values
    )
    inventory_ready = (
        all(value["rc"] == 0 for value in observations.values())
        and bool(dimm_ids)
        and topology_verified
    )
    return {
        "schema_version": 1,
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "binary": {
            "available": observations["version"]["rc"] == 0,
            "version_rc": observations["version"]["rc"],
            "version": version_text,
        },
        "hardware": {
            "present": observations["dimms"]["rc"] == 0 and bool(dimm_ids),
            "dimm_ids": dimm_ids,
            "socket_ids": sockets,
            "topology_verified": topology_verified,
            "manageable": contains_all_state(dimms, "ManageabilityState", {"manageable"}),
            "healthy": contains_all_state(dimms, "HealthState", {"healthy", "normal"}),
            "security_safe_for_goal": security_safe,
        },
        "capabilities": {
            "command_rc": observations["capabilities"]["rc"],
            "platform_config_supported": first_value(capabilities, "PlatformConfigSupported") == "1",
            "current_volatile_mode": current_volatile_mode,
            "allowed_volatile_mode": first_value(capabilities, "AllowedVolatileMode"),
            "allowed_app_direct_mode": first_value(capabilities, "AllowedAppDirectMode"),
            "modes_supported": modes_supported,
            "memory_mode_supported": (
                "2lm" in normalized_modes or "memorymode" in normalized_modes
            ),
            "app_direct_supported": "appdirect" in normalized_modes,
        },
        "memory_resources": {
            "command_rc": observations["memory_resources"]["rc"],
            "volatile_pmem_bytes": volatile_pmem,
            "app_direct_pmem_bytes": app_direct,
            "cache_ddr_bytes": cache_ddr,
            "current_mode": current_mode,
            "memory_mode_verified": current_mode in {"memory-mode", "mixed"} and cache_ddr > 0,
        },
        "regions": {
            "persistent_memory_types": region_types,
        },
        "pending_goal": {
            "command_rc": observations["goal"]["rc"],
            "present": pending_goal,
        },
        "ndctl": {
            "dimms": ndctl_dimms,
            "regions": regions,
            "namespaces": namespaces,
            "namespace_count": len(namespaces),
        },
        "commands": {
            key: {
                "rc": value["rc"],
                "log": str(log_dir / f"{safe_name(key)}.txt") if log_dir else "",
            }
            for key, value in observations.items()
        },
        "readiness": {
            "tool_ready": observations["version"]["rc"] == 0,
            "inventory_ready": inventory_ready,
            "goal_change_supported": (
                inventory_ready
                and first_value(capabilities, "PlatformConfigSupported") == "1"
            ),
            "settled": not pending_goal,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture-dir", type=Path)
    parser.add_argument("--fixture-base-dir", type=Path)
    parser.add_argument("--log-dir", type=Path)
    args = parser.parse_args()
    observations = {
        name: execute(
            argv,
            args.fixture_dir,
            args.fixture_base_dir,
            args.log_dir,
            name,
        )
        for name, argv in COMMANDS.items()
    }
    print(json.dumps(normalize(observations, args.log_dir), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
