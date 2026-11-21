#!/usr/bin/env python3
"""Collect a vendor-neutral CPU, NUMA, memory, and PMem host snapshot."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
from pathlib import Path
from typing import Any


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def run_command(argv: list[str]) -> tuple[int, str]:
    try:
        result = subprocess.run(argv, check=False, capture_output=True, text=True)
    except OSError:
        return 127, ""
    return result.returncode, result.stdout


class Source:
    def __init__(self, fixture_dir: Path | None) -> None:
        self.fixture_dir = fixture_dir

    def file(self, live_path: str, fixture_name: str) -> str:
        path = self.fixture_dir / fixture_name if self.fixture_dir else Path(live_path)
        return read_text(path)

    def command(self, argv: list[str], fixture_name: str) -> tuple[int, str]:
        if not self.fixture_dir:
            return run_command(argv)
        rc_text = read_text(self.fixture_dir / f"{fixture_name}.rc").strip()
        rc = int(rc_text) if rc_text else 0
        return rc, read_text(self.fixture_dir / f"{fixture_name}.txt")


def parse_key_values(text: str, separator: str = ":") -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        if separator not in raw_line:
            continue
        key, value = raw_line.split(separator, 1)
        values[key.strip()] = value.strip()
    return values


def parse_cpuinfo(text: str) -> dict[str, Any]:
    sections = [section for section in text.strip().split("\n\n") if section.strip()]
    first = parse_key_values(sections[0]) if sections else {}
    flags = first.get("flags", first.get("Features", "")).split()
    aliases = {
        "sse4_1": "sse4.1",
        "sse4_2": "sse4.2",
    }
    normalized_flags = sorted({aliases.get(flag, flag) for flag in flags})
    return {
        "vendor_id": first.get("vendor_id", ""),
        "model_name": first.get("model name", first.get("Processor", "")),
        "flags": normalized_flags,
    }


def parse_lscpu_summary(text: str) -> dict[str, str]:
    values = parse_key_values(text)
    return {
        "architecture": values.get("Architecture", ""),
        "byte_order": values.get("Byte Order", ""),
        "virtualization": values.get("Virtualization", ""),
    }


def parse_lscpu_rows(text: str) -> list[dict[str, int | bool]]:
    rows: list[dict[str, int | bool]] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = [field.strip() for field in line.split(",")]
        if len(fields) < 5 or not fields[0].isdigit():
            continue
        online = fields[3].lower() not in {"n", "no", "false", "off", "0"}
        if not online:
            continue
        rows.append(
            {
                "cpu": int(fields[0]),
                "socket": int(fields[1]) if fields[1].lstrip("-").isdigit() else -1,
                "core": int(fields[2]) if fields[2].lstrip("-").isdigit() else int(fields[0]),
                "online": True,
                "node": int(fields[4]) if fields[4].lstrip("-").isdigit() else -1,
            }
        )
    return sorted(rows, key=lambda row: int(row["cpu"]))


def physical_cpu_selection(rows: list[dict[str, int | bool]]) -> dict[str, Any]:
    selected: list[int] = []
    excluded: list[int] = []
    seen: set[tuple[int, int]] = set()
    for row in rows:
        key = (int(row["socket"]), int(row["core"]))
        cpu = int(row["cpu"])
        if key in seen:
            excluded.append(cpu)
        else:
            seen.add(key)
            selected.append(cpu)
    mask_value = sum(1 << cpu for cpu in selected)
    return {
        "logical_count": len(rows),
        "physical_core_count": len(selected),
        "selected_logical_cpus": selected,
        "excluded_smt_siblings": excluded,
        "selected_cpu_list": ",".join(str(cpu) for cpu in selected),
        "selected_cpu_mask": f"0x{mask_value:x}",
    }


def parse_meminfo(text: str) -> dict[str, int]:
    values: dict[str, int] = {}
    for raw_line in text.splitlines():
        match = re.match(r"^([A-Za-z_()]+):\s+(\d+)", raw_line)
        if match:
            values[match.group(1)] = int(match.group(2))
    return {
        "total_kib": values.get("MemTotal", 0),
        "available_kib": values.get("MemAvailable", 0),
        "swap_total_kib": values.get("SwapTotal", 0),
        "swap_free_kib": values.get("SwapFree", 0),
    }


def parse_node_online(text: str) -> list[int]:
    nodes: list[int] = []
    for segment in text.strip().split(","):
        if not segment:
            continue
        if "-" in segment:
            start, end = segment.split("-", 1)
            if start.isdigit() and end.isdigit():
                nodes.extend(range(int(start), int(end) + 1))
        elif segment.isdigit():
            nodes.append(int(segment))
    return sorted(set(nodes))


def parse_node_memory_kib(text: str) -> int:
    match = re.search(r"MemTotal:\s+(\d+)\s+kB", text)
    return int(match.group(1)) if match else 0


def collect_numa(source: Source) -> dict[str, Any]:
    node_ids = parse_node_online(
        source.file("/sys/devices/system/node/online", "node-online.txt")
    )
    nodes: list[dict[str, Any]] = []
    for node_id in node_ids:
        nodes.append(
            {
                "id": node_id,
                "cpu_list": source.file(
                    f"/sys/devices/system/node/node{node_id}/cpulist",
                    f"node{node_id}-cpulist.txt",
                ).strip(),
                "memory_total_kib": parse_node_memory_kib(
                    source.file(
                        f"/sys/devices/system/node/node{node_id}/meminfo",
                        f"node{node_id}-meminfo.txt",
                    )
                ),
                "distance": [
                    int(value)
                    for value in source.file(
                        f"/sys/devices/system/node/node{node_id}/distance",
                        f"node{node_id}-distance.txt",
                    ).split()
                    if value.isdigit()
                ],
            }
        )
    return {"count": len(nodes), "nodes": nodes}


def positive_capacity(text: str) -> bool:
    for raw_value in re.findall(r"MemoryCapacity[^0-9]*([0-9][0-9,]*)", text, re.I):
        if int(raw_value.replace(",", "")) > 0:
            return True
    return False


def collect_memory_mode(source: Source) -> dict[str, Any]:
    ipmctl_rc, ipmctl_text = source.command(
        ["/usr/local/bin/ipmctl", "show", "-memoryresources"],
        "ipmctl-memoryresources",
    )
    dmidecode_rc, dmidecode_text = source.command(
        ["dmidecode", "--type", "memory"], "dmidecode-memory"
    )
    persistent_pattern = re.compile(
        r"(persistent memory|non-volatile|optane|memory mode)", re.I
    )
    if ipmctl_rc == 0 and positive_capacity(ipmctl_text):
        classification = "verified"
        reason = "ipmctl reported positive MemoryCapacity."
    elif dmidecode_rc == 0 and persistent_pattern.search(dmidecode_text):
        classification = "consistent"
        reason = "DMI memory records contain persistent-memory evidence."
    else:
        classification = "unknown"
        reason = "No positive Memory Mode evidence was available."
    return {
        "classification": classification,
        "reason": reason,
        "ipmctl_available": ipmctl_rc != 127,
        "ipmctl_rc": ipmctl_rc,
        "dmidecode_available": dmidecode_rc != 127,
        "dmidecode_rc": dmidecode_rc,
    }


def build_snapshot(source: Source) -> dict[str, Any]:
    lscpu_rc, lscpu_text = source.command(["lscpu"], "lscpu-summary")
    parse_rc, parse_text = source.command(
        ["lscpu", "--parse=CPU,SOCKET,CORE,ONLINE,NODE"], "lscpu-parse"
    )
    rows = parse_lscpu_rows(parse_text if parse_rc == 0 else "")
    cpu = parse_cpuinfo(source.file("/proc/cpuinfo", "cpuinfo.txt"))
    cpu.update(parse_lscpu_summary(lscpu_text if lscpu_rc == 0 else ""))
    cpu.update(physical_cpu_selection(rows))
    cpu["topology_rows"] = rows
    return {
        "schema_version": 1,
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "cpu": cpu,
        "memory": parse_meminfo(source.file("/proc/meminfo", "meminfo.txt")),
        "numa": collect_numa(source),
        "memory_mode": collect_memory_mode(source),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture-dir", type=Path)
    args = parser.parse_args()
    snapshot = build_snapshot(Source(args.fixture_dir))
    print(json.dumps(snapshot, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
