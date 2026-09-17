#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Running unit tests ==="
node --test "$DIR/tests/model.test.js"

echo "=== Validating Omarchy plugin manifest ==="
omarchy plugin validate "$DIR"

echo "✓ All checks passed successfully!"
