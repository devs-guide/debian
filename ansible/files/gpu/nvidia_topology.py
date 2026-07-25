#!/usr/bin/env python3
"""Parse the GPU label matrix emitted by ``nvidia-smi topo -m``.

The matrix labels (for example ``GPU0``) are local to the specific
``nvidia-smi`` invocation.  They are deliberately not CUDA indices, UUIDs, or
PCI identities.  Callers must first resolve a current snapshot and then pass
the exact labels from that snapshot.
"""

from __future__ import annotations

import json
import re
from typing import Any


GPU_LABEL = re.compile(r"^GPU[0-9]+$")
NVLINK_ROUTE = re.compile(r"^NV(?P<count>[0-9]+)$")


class TopologyParseError(ValueError):
    """A topology table was absent, malformed, or lacked a requested pair."""


def parse_topology(text: str) -> dict[str, Any]:
    """Return the labels and directed routes from a raw ``topo -m`` capture."""

    labels: list[str] | None = None
    matrix: dict[str, dict[str, str]] = {}

    for raw_line in text.splitlines():
        tokens = raw_line.split()
        if not tokens or raw_line.lstrip().startswith("#"):
            continue

        if labels is None:
            # ``nvidia-smi topo -m`` emits its header as an indented row.  GPU
            # route rows are not indented, so accepting any line containing a
            # GPU label can accidentally treat a data row as the header.
            if not raw_line[:1].isspace():
                continue
            candidate_labels: list[str] = []
            for token in tokens:
                if GPU_LABEL.fullmatch(token):
                    candidate_labels.append(token)
                elif candidate_labels:
                    break
            if candidate_labels:
                labels = candidate_labels
            continue

        source_label = tokens[0]
        if source_label not in labels:
            continue
        routes = tokens[1 : 1 + len(labels)]
        if len(routes) != len(labels):
            raise TopologyParseError(
                f"topology row for {source_label!r} has {len(routes)} GPU routes; "
                f"expected {len(labels)}"
            )
        matrix[source_label] = dict(zip(labels, routes, strict=True))

    if not labels:
        raise TopologyParseError("no GPU header labels were found in topology output")
    if not matrix:
        raise TopologyParseError("no GPU route rows were found in topology output")
    missing_rows = [label for label in labels if label not in matrix]
    if missing_rows:
        raise TopologyParseError(
            "topology output is missing route rows for "
            f"{missing_rows!r}; discovered_labels={labels!r}"
        )

    return {"labels": labels, "matrix": matrix}


def pair_result(text: str, source_label: str, destination_label: str) -> dict[str, Any]:
    """Return a machine-readable route result for one directed matrix pair."""

    parsed = parse_topology(text)
    labels = parsed["labels"]
    matrix = parsed["matrix"]
    if source_label not in labels or destination_label not in labels:
        raise TopologyParseError(
            "requested topology label was not found; "
            f"source={source_label!r}, destination={destination_label!r}, "
            f"discovered_labels={labels!r}"
        )
    route = matrix.get(source_label, {}).get(destination_label)
    if route is None:
        raise TopologyParseError(
            "selected source/destination pair was not found in topology output; "
            f"source={source_label!r}, destination={destination_label!r}, "
            f"discovered_labels={labels!r}"
        )
    match = NVLINK_ROUTE.fullmatch(route)
    return {
        "passed": True,
        "source_label": source_label,
        "destination_label": destination_label,
        "route": route,
        "bonded_nvlink_count": int(match.group("count")) if match else 0,
        "labels": labels,
    }


def emit_error(error: Exception) -> None:
    print(json.dumps({"passed": False, "error": str(error)}, sort_keys=True))
