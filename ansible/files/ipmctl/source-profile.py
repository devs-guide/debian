#!/usr/bin/env python3
"""Validate one exact reviewed ipmctl and edk2 source tuple."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit


FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
TOKEN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")


def fail(message: str) -> None:
    print(f"ipmctl-source-profile: {message}", file=sys.stderr)
    raise SystemExit(64)


def validate_url(value: str, label: str) -> None:
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or not parsed.path.endswith(".git")
        or ".." in parsed.path.split("/")
        or re.search(r"[\x00-\x20\x7f`$;&|<>\\]", value)
    ):
        fail(f"{label} must be a credential-free HTTPS Git URL ending in .git")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", required=True, type=Path)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--repository-url", required=True)
    parser.add_argument("--release", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--edk2-repository-url", required=True)
    parser.add_argument("--edk2-release", required=True)
    parser.add_argument("--edk2-commit", required=True)
    args = parser.parse_args()

    for value, label in (
        (args.profile, "profile"),
        (args.release, "release"),
        (args.edk2_release, "edk2 release"),
    ):
        if not TOKEN.fullmatch(value):
            fail(f"{label} contains unsupported characters")
    validate_url(args.repository_url, "repository URL")
    validate_url(args.edk2_repository_url, "edk2 repository URL")
    if not FULL_SHA.fullmatch(args.commit):
        fail("commit must be a lowercase full 40-character SHA")
    if not FULL_SHA.fullmatch(args.edk2_commit):
        fail("edk2 commit must be a lowercase full 40-character SHA")

    try:
        document = json.loads(args.matrix.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot decode compatibility matrix: {error}")
    profiles = document.get("profiles", [])
    matches = [
        profile
        for profile in profiles
        if isinstance(profile, dict)
        and profile.get("feature") == "ipmctl"
        and profile.get("id") == args.profile
    ]
    if document.get("schema_version") != 1 or len(matches) != 1:
        fail("matrix must contain exactly one matching schema-version-1 profile")

    profile = matches[0]
    requested = {
        "repository_url": args.repository_url,
        "release": args.release,
        "commit": args.commit,
        "edk2_repository_url": args.edk2_repository_url,
        "edk2_release": args.edk2_release,
        "edk2_commit": args.edk2_commit,
    }
    mismatches = {
        key: {"reviewed": profile.get(key), "requested": value}
        for key, value in requested.items()
        if profile.get(key) != value
    }
    if mismatches:
        fail("source tuple is not reviewed: " + json.dumps(mismatches, sort_keys=True))
    print(json.dumps(profile, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
