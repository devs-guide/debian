#!/usr/bin/env python3
"""CLI wrapper for the shared NVIDIA topology-label parser.

The source and destination values are exact labels captured from the same
``nvidia-smi topo -m`` output (for example ``GPU0``). They are not UUIDs, PCI
addresses, or CUDA device indices.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from nvidia_topology import TopologyParseError, emit_error, pair_result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--topology", required=True)
    parser.add_argument("--source-label", required=True)
    parser.add_argument("--destination-label", required=True)
    arguments = parser.parse_args()
    try:
        print(json.dumps(
            pair_result(
                Path(arguments.topology).read_text(encoding="utf-8"),
                arguments.source_label,
                arguments.destination_label,
            ),
            sort_keys=True,
        ))
    except (OSError, TopologyParseError) as error:
        emit_error(error)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
