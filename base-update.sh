#!/usr/bin/env bash
set -euo pipefail

sudo dnf -y --refresh upgrade

date -u +"%Y-%m-%dT%H:%M:%SZ" |
  sudo tee /etc/agent-base-built-at >/dev/null
