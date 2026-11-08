#!/usr/bin/env bash
# Reports whether Desert Ant Labs released a newer desert-ant-core than the version Package.swift
# pins. Changes nothing; see README.md (Build) for how to move to a new version.
set -euo pipefail
cd "$(dirname "$0")/../.."
pinned=$(grep -o 'exact: "[0-9.]*"' Package.swift | grep -o '[0-9][0-9.]*')
latest=$(git ls-remote --tags --refs https://github.com/Desert-Ant-Labs/desert-ant-core.git \
  | sed 's|.*refs/tags/v\{0,1\}||' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
echo "desert-ant-core pinned: $pinned, latest release: $latest"
if [ "$pinned" = "$latest" ]; then echo "Up to date."; else echo "Newer version available. Read its release notes before moving."; fi
