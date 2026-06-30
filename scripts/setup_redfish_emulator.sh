#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
EMU_DIR="$ROOT_DIR/Redfish-Interface-Emulator"

if [[ ! -d "$EMU_DIR" ]]; then
  echo "Redfish-Interface-Emulator repo not found at: $EMU_DIR" >&2
  exit 1
fi

cd "$EMU_DIR"

python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

echo
echo "Redfish Interface Emulator environment is ready."
echo "Run: ./scripts/run_redfish_emulator.sh static"

