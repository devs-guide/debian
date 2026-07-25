#!/usr/bin/env python3
"""Collect a vendor-neutral PCI snapshot with NVIDIA runtime enrichment.

This helper intentionally reads host state only.  The Ansible task that calls
it owns persistence to ``/etc/ansible/debian/facts/gpu.yml``.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import shutil
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from nvidia_topology import TopologyParseError, parse_topology


PCI_HEADER = re.compile(
    r"^(?P<pci>[0-9a-fA-F:.]+)\s+.+?\[(?P<class>[0-9a-fA-F]{4})\]:.+?\[(?P<vendor>[0-9a-fA-F]{4}):[0-9a-fA-F]{4}\]"
)
PCI_ADDRESS = re.compile(
    r"^(?:(?P<domain>[0-9a-fA-F]+):)?(?P<bus>[0-9a-fA-F]{2}):(?P<device>[0-9a-fA-F]{2})\.(?P<function>[0-7])$"
)
VENDORS = {"10de": "nvidia", "1002": "amd", "8086": "intel"}


def command_output(argv: list[str]) -> tuple[int, str, str]:
    completed = subprocess.run(argv, capture_output=True, text=True, check=False)
    return completed.returncode, completed.stdout, completed.stderr


def canonical_pci(value: str) -> str:
    match = PCI_ADDRESS.fullmatch(value.strip())
    if not match:
        raise ValueError(f"unsupported PCI address: {value!r}")
    domain = int(match.group("domain") or "0", 16)
    bus = int(match.group("bus"), 16)
    device = int(match.group("device"), 16)
    function = int(match.group("function"), 10)
    return f"{domain:04x}:{bus:02x}:{device:02x}.{function}"


def pci_aliases(*values: str) -> list[str]:
    aliases: set[str] = set()
    for value in values:
        if not value:
            continue
        aliases.add(value.lower())
        try:
            aliases.add(canonical_pci(value))
        except ValueError:
            pass
    return sorted(aliases)


def parse_lspci(text: str) -> list[dict[str, Any]]:
    devices: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for line in text.splitlines():
        header = PCI_HEADER.match(line)
        if header:
            if current:
                devices.append(current)
            class_code = header.group("class").lower()
            vendor_id = header.group("vendor").lower()
            current = {
                "pci_bus_id": canonical_pci(header.group("pci")),
                "pci_bus_aliases": pci_aliases(header.group("pci")),
                "vendor": VENDORS.get(vendor_id, "other"),
                "vendor_id": vendor_id,
                "class_code": class_code,
                "kernel_driver": "",
            }
            continue
        if current and line.lstrip().startswith("Kernel driver in use:"):
            current["kernel_driver"] = line.split(":", 1)[1].strip()
    if current:
        devices.append(current)
    return [device for device in devices if device["class_code"].startswith(("03", "12"))]


def nvidia_runtime() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if not shutil.which("nvidia-smi"):
        return [], {"available": False, "reason": "nvidia-smi is not available"}

    query = [
        "nvidia-smi",
        "--query-gpu=index,name,uuid,pci.bus_id,memory.total,driver_version,compute_cap",
        "--format=csv,noheader",
    ]
    rc, stdout, stderr = command_output(query)
    if rc != 0:
        return [], {"available": False, "reason": stderr.strip() or stdout.strip() or f"nvidia-smi rc={rc}"}

    _, gpu_list, _ = command_output(["nvidia-smi", "-L"])
    mig_enabled = "MIG" in gpu_list
    rows: list[dict[str, Any]] = []
    for row in csv.reader(io.StringIO(stdout), skipinitialspace=True):
        if len(row) != 7:
            raise ValueError(f"unexpected nvidia-smi inventory row: {row!r}")
        reported_pci = row[3].strip()
        rows.append(
            {
                "index": int(row[0]),
                "topology_label": "",
                "name": row[1].strip(),
                "uuid": row[2].strip(),
                "pci_bus_id": canonical_pci(reported_pci),
                "pci_bus_aliases": pci_aliases(reported_pci),
                "memory_total": row[4].strip(),
                "driver_version": row[5].strip(),
                "compute_capability": row[6].strip(),
                "mig_enabled": mig_enabled,
            }
        )

    topology: dict[str, Any] = {"available": False}
    topology_rc, topology_stdout, topology_stderr = command_output(["nvidia-smi", "topo", "-m"])
    if topology_rc == 0:
        try:
            topology = {"available": True, "raw": topology_stdout, **parse_topology(topology_stdout)}
            labels = set(topology["labels"])
            for row in rows:
                expected_label = f"GPU{row['index']}"
                row["topology_label"] = expected_label if expected_label in labels else ""
        except TopologyParseError as error:
            topology = {"available": False, "raw": topology_stdout, "reason": str(error)}
    else:
        topology = {"available": False, "reason": topology_stderr.strip() or f"nvidia-smi topo -m rc={topology_rc}"}
    return rows, {"available": True, "topology": topology}


def merge_devices(pci_devices: list[dict[str, Any]], nvidia_devices: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_pci = {device["pci_bus_id"]: device for device in pci_devices}
    for runtime in nvidia_devices:
        device = by_pci.get(runtime["pci_bus_id"])
        if device is None:
            device = {
                "pci_bus_id": runtime["pci_bus_id"],
                "pci_bus_aliases": runtime["pci_bus_aliases"],
                "vendor": "nvidia",
                "vendor_id": "10de",
                "class_code": "",
                "kernel_driver": "",
            }
            by_pci[device["pci_bus_id"]] = device
        device["pci_bus_aliases"] = sorted(set(device["pci_bus_aliases"]) | set(runtime["pci_bus_aliases"]))
        device["nvidia"] = runtime
    return sorted(by_pci.values(), key=lambda device: device["pci_bus_id"])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vendor", choices=("auto", "nvidia"), default="auto")
    args = parser.parse_args()

    lspci_text = ""
    pci_inventory_available = False
    if shutil.which("lspci"):
        lspci_rc, lspci_text, _ = command_output(["lspci", "-Dnnk"])
        pci_inventory_available = lspci_rc == 0
    pci_devices = parse_lspci(lspci_text) if pci_inventory_available else []
    nvidia_devices, nvidia = nvidia_runtime()
    devices = merge_devices(pci_devices, nvidia_devices)
    if args.vendor == "nvidia":
        devices = [device for device in devices if device["vendor"] == "nvidia"]

    payload = {
        "schema_version": 1,
        "generated_at": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "requested_vendor": args.vendor,
        "pci_inventory_available": pci_inventory_available,
        "devices": devices,
        "topology": {"nvidia_smi": nvidia.get("topology", {"available": False})},
        "runtime": {"nvidia": {key: value for key, value in nvidia.items() if key != "topology"}},
    }
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, TopologyParseError) as error:
        print(json.dumps({"error": str(error)}, sort_keys=True), file=sys.stderr)
        raise SystemExit(1)
