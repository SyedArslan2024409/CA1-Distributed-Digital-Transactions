#!/usr/bin/env bash
# Starts Ganache (if not running), installs Python deps, runs the test script.
set -e

pip install --quiet web3 py-solc-x

if ! curl -s -X POST http://127.0.0.1:8545 >/dev/null 2>&1; then
  echo "Starting Ganache on port 8545..."
  npx ganache --port 8545 --deterministic > ganache.log 2>&1 &
  sleep 6
fi

python test_insurance.py
