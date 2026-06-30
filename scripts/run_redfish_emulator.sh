#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
EMU_DIR="$ROOT_DIR/Redfish-Interface-Emulator"
MODE="${1:-static}"
PORT="${REDFISH_EMULATOR_PORT:-5001}"

if [[ ! -d "$EMU_DIR" ]]; then
  echo "Redfish-Interface-Emulator repo not found at: $EMU_DIR" >&2
  exit 1
fi

if [[ ! -x "$EMU_DIR/.venv/bin/python" ]]; then
  echo "Missing emulator virtualenv. Run ./scripts/setup_redfish_emulator.sh first." >&2
  exit 1
fi

case "$MODE" in
  static)
    CONFIG_FILE="emulator-config_static.json"
    ;;
  dynamic-populate)
    CONFIG_FILE="emulator-config_dynamic_populate.json"
    ;;
  dynamic-empty)
    CONFIG_FILE="emulator-config_dynamic_dontpopulated.json"
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    echo "Usage: ./scripts/run_redfish_emulator.sh [static|dynamic-populate|dynamic-empty]" >&2
    exit 1
    ;;
esac

cd "$EMU_DIR"
cp "$CONFIG_FILE" emulator-config.json

echo "Starting Redfish Interface Emulator"
echo "Mode: $MODE"
echo "Port: $PORT"
echo "Config: $CONFIG_FILE"

exec .venv/bin/python emulator.py -port "$PORT"
