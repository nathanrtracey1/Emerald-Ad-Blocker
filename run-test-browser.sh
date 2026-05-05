#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check Swift is available
if ! command -v swift &>/dev/null; then
  echo "Swift not found. Install Xcode Command Line Tools:"
  echo "  xcode-select --install"
  exit 1
fi

# Warn if output files are missing
if [ ! -f "$SCRIPT_DIR/output/adblock.json" ]; then
  echo "Warning: output/adblock.json not found."
  echo "Run 'python3 src/build.py' first to generate the rule files."
  echo ""
fi

echo "Building and launching Emerald test browser…"
cd "$SCRIPT_DIR/TestApp"
swift run
