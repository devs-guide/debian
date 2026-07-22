#!/usr/bin/env python3
"""Extract one selected GPU-pair route token from `nvidia-smi topo -m`."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


GPU_TOKEN = re.compile(r"^GPU(?P<index>\d+)$")
NVLINK_TOKEN = re.compile(r"^NV(?P<count>\d+)$")


def parse_route(topology: str, source_index: int, destination_index: int) -> str:
    source_token = f"GPU{source_index}"
    destination_token = f"GPU{destination_index}"
    header: list[str] | None = None
    for raw_line in topology.splitlines():
        tokens = raw_line.split()
        if not tokens:
            continue
        if header is None and source_token in tokens and destination_token in tokens:
            gpu_tokens = [token for token in tokens if GPU_TOKEN.fullmatch(token)]
            if gpu_tokens:
                header = gpu_tokens
            continue
        if header is not None and tokens[0] == source_token:
            try:
                return tokens[header.index(destination_token) + 1]
            except (ValueError, IndexError) as error:
                raise ValueError("selected destination is absent from topology row") from error
    raise ValueError("selected source/destination pair was not found in topology output")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--topology", required=True, type=Path)
    parser.add_argument("--source-index", required=True, type=int)
    parser.add_argument("--destination-index", required=True, type=int)
    arguments = parser.parse_args()
    try:
        route = parse_route(arguments.topology.read_text(encoding="utf-8"), arguments.source_index, arguments.destination_index)
    except (OSError, ValueError) as error:
        print(json.dumps({"passed": False, "error": str(error)}))
        return 1
    nvlink_match = NVLINK_TOKEN.fullmatch(route)
    print(
        json.dumps(
            {
                "passed": True,
                "source_index": arguments.source_index,
                "destination_index": arguments.destination_index,
                "route": route,
                "classification": "nvlink_active_candidate" if nvlink_match else "non_nvlink_route",
                "bonded_nvlink_count": int(nvlink_match.group("count")) if nvlink_match else 0,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
