#!/usr/bin/env python3
"""Validate an exact, reviewed LLM source tuple without third-party modules."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
TOKEN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")


def fail(message: str) -> None:
    print(f"source-profile: {message}", file=sys.stderr)
    raise SystemExit(64)


def validate_repository_url(value: str, label: str) -> None:
    parsed = urlsplit(value)
    try:
        port = parsed.port
    except ValueError:
        fail(f"{label} contains an invalid port")
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or port is not None
        or parsed.query
        or parsed.fragment
        or not parsed.path.endswith(".git")
        or ".." in parsed.path.split("/")
        or re.search(r"[\x00-\x20\x7f`$;&|<>\\]", value)
    ):
        fail(f"{label} must be a credential-free HTTPS Git URL ending in .git")


def validate_sha(value: str, label: str) -> None:
    if not FULL_SHA.fullmatch(value):
        fail(f"{label} must be a lowercase full 40-character commit")


def load_matrix(path: Path) -> dict[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot decode compatibility matrix {path}: {error}")
    if document.get("schema_version") != 1 or not isinstance(document.get("profiles"), list):
        fail("compatibility matrix must contain schema_version 1 and a profiles list")
    return document


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", required=True, type=Path)
    parser.add_argument("--feature", required=True, choices=("llamacpp", "ktransformers"))
    parser.add_argument("--profile", required=True)
    parser.add_argument("--repository-url", required=True)
    parser.add_argument("--release", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--sglang-repository-url", default="")
    parser.add_argument("--sglang-commit", default="")
    args = parser.parse_args()

    if not TOKEN.fullmatch(args.profile):
        fail("profile contains unsupported characters")
    if not TOKEN.fullmatch(args.release):
        fail("release contains unsupported characters")
    validate_repository_url(args.repository_url, "repository URL")
    validate_sha(args.commit, "commit")
    if args.feature == "ktransformers":
        validate_repository_url(args.sglang_repository_url, "SGLang repository URL")
        validate_sha(args.sglang_commit, "SGLang commit")

    matrix = load_matrix(args.matrix)
    matches = [
        item
        for item in matrix["profiles"]
        if isinstance(item, dict)
        and item.get("feature") == args.feature
        and item.get("id") == args.profile
    ]
    if len(matches) != 1:
        fail(f"profile {args.profile!r} is not a unique reviewed {args.feature} profile")
    profile = matches[0]

    expected = {
        "repository_url": args.repository_url,
        "release": args.release,
        "commit": args.commit,
    }
    if args.feature == "ktransformers":
        expected.update(
            {
                "sglang_repository_url": args.sglang_repository_url,
                "sglang_commit": args.sglang_commit,
            }
        )
    mismatches = {
        key: {"expected": profile.get(key), "requested": value}
        for key, value in expected.items()
        if profile.get(key) != value
    }
    if mismatches:
        fail(
            "requested source tuple is not approved by the selected profile: "
            + json.dumps(mismatches, sort_keys=True)
        )

    print(json.dumps(profile, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
