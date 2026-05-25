#!/usr/bin/env bash
set -euo pipefail
# Usage: run_k6.sh <test_file> <target_url>
# Example: K6_HOST=http://1.2.3.4:8080 ./run_k6.sh cs3/load_tests/k6/portal_load_test.js

TEST_FILE="$1"
TARGET="$2"

if [[ -z "$TEST_FILE" || -z "$TARGET" ]]; then
  echo "Usage: $0 <test_file> <target_url>"
  exit 2
fi

# Run k6 in docker so no local install required
docker run --rm -i -e K6_HOST="$TARGET" -v "$(pwd)":/scripts loadimpact/k6 run "/scripts/$TEST_FILE"
