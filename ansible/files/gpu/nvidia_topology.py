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
import unicodedata
from typing import Any


GPU_LABEL = re.compile(r"^GPU[0-9]+$")
NVLINK_ROUTE = re.compile(r"^NV(?P<count>[0-9]+)$")
ANSI_ESCAPE = re.compile(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


class TopologyParseError(ValueError):
    """A topology table was absent, malformed, or lacked a requested pair."""


def normalize_topology_line(raw_line: str) -> str:
    """Remove terminal decoration while preserving matrix indentation."""

    undecorated = ANSI_ESCAPE.sub("", raw_line).replace("\ufeff", "")
    normalized: list[str] = []
    for character in undecorated:
        if character == "\t":
            normalized.append(" ")
        elif unicodedata.category(character) in {"Cc", "Cf"}:
            continue
        else:
            normalized.append(character)
    return "".join(normalized)


def _header_labels(tokens: list[str], indented: bool) -> list[str]:
    if not indented:
        return []

    labels: list[str] = []
    for token in tokens:
        if GPU_LABEL.fullmatch(token):
            labels.append(token)
            continue
        if token.upper().startswith("GPU"):
            raise TopologyParseError(f"malformed GPU label in topology header: {token!r}")
        if labels:
            break

    # Route rows can be indented by wrappers or copied output. The real matrix
    # header continues with the CPU-affinity columns after its GPU labels.
    if labels and "CPU" in tokens[len(labels) :]:
        return labels
    return []


def parse_topology(text: str) -> dict[str, Any]:
    """Return the labels and directed routes from a raw ``topo -m`` capture."""

    headers: list[list[str]] = []
    route_rows: list[tuple[str, list[str]]] = []
    seen_route_labels: set[str] = set()

    for raw_line in text.splitlines():
        normalized_line = normalize_topology_line(raw_line)
        tokens = normalized_line.split()
        if not tokens or normalized_line.lstrip().startswith("#"):
            continue

        candidate_header = _header_labels(tokens, normalized_line[:1].isspace())
        if candidate_header:
            headers.append(candidate_header)
            continue

        source_label = tokens[0]
        if source_label.upper().startswith("GPU") and not GPU_LABEL.fullmatch(source_label):
            raise TopologyParseError(f"malformed GPU route-row label: {source_label!r}")
        if not GPU_LABEL.fullmatch(source_label):
            continue
        if source_label in seen_route_labels:
            raise TopologyParseError(f"duplicate topology route row for {source_label!r}")
        seen_route_labels.add(source_label)
        route_rows.append((source_label, tokens[1:]))

    if not headers:
        raise TopologyParseError("no GPU header labels were found in topology output")
    if len(headers) != 1:
        raise TopologyParseError(f"expected one GPU topology header; found {len(headers)}")

    labels = headers[0]
    if len(labels) != len(set(labels)):
        raise TopologyParseError(f"duplicate GPU labels in topology header: {labels!r}")
    if not route_rows:
        raise TopologyParseError("no GPU route rows were found in topology output")

    row_labels = [source_label for source_label, _ in route_rows]
    missing_rows = [label for label in labels if label not in seen_route_labels]
    unexpected_rows = [label for label in row_labels if label not in set(labels)]
    if missing_rows or unexpected_rows:
        raise TopologyParseError(
            "topology header and route rows disagree; "
            f"header_labels={labels!r}, row_labels={row_labels!r}, "
            f"missing_rows={missing_rows!r}, unexpected_rows={unexpected_rows!r}"
        )

    matrix: dict[str, dict[str, str]] = {}
    for source_label, row_tokens in route_rows:
        routes = row_tokens[: len(labels)]
        if len(routes) != len(labels):
            raise TopologyParseError(
                f"topology row for {source_label!r} has {len(routes)} GPU routes; "
                f"expected {len(labels)}"
            )
        matrix[source_label] = dict(zip(labels, routes, strict=True))

    return {
        "labels": labels,
        "row_labels": row_labels,
        "matrix": matrix,
        "label_source": "normalized-topology-header",
    }


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
