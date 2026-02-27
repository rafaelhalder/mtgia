#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Usa TELEMETRY_RETENTION_DAYS do ambiente (ou .env via script Dart).
dart run bin/cleanup_optimize_telemetry.dart "$@"
