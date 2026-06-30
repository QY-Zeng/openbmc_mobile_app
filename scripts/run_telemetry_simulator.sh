#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

BASE_URL="${REDFISH_SIMULATOR_BASE_URL:-http://127.0.0.1:5001}"
CHASSIS_IDS="${REDFISH_SIMULATOR_CHASSIS_IDS:-}"
CHASSIS_ID="${REDFISH_SIMULATOR_CHASSIS_ID:-}"
INTERVAL="${REDFISH_SIMULATOR_INTERVAL:-2.0}"

ARGS=(
  --base-url "$BASE_URL"
  --interval "$INTERVAL"
)

if [[ -n "$CHASSIS_IDS" ]]; then
  ARGS+=(--chassis-id "$CHASSIS_IDS")
elif [[ -n "$CHASSIS_ID" ]]; then
  ARGS+=(--chassis-id "$CHASSIS_ID")
fi

exec python3 "$ROOT_DIR/scripts/telemetry_simulator.py" "${ARGS[@]}" "$@"
