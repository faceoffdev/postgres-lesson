#!/usr/bin/env bash
set -euo pipefail

curl -fsS http://localhost:8080/healthz | grep -x "ok"
echo "healthz smoke passed"
