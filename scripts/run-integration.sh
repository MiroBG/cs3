#!/usr/bin/env bash
set -euo pipefail

# Run integration and smoke tests locally (Python pytest)
# Usage: ./scripts/run-integration.sh

cd "$(dirname "$0")/.." || exit 1

echo "Installing test requirements"
if [[ -f cs3/tests/requirements.txt ]]; then
  python3 -m pip install --user -r cs3/tests/requirements.txt
fi

echo "Running pytest for CS3 tests"
pytest -q cs3/tests
