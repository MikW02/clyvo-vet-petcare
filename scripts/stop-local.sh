#!/usr/bin/env bash
# Tear down the local stack. Pass --purge to also drop the named volume
# (deletes all Oracle data!).
set -euo pipefail

docker rm -f clyvo-petcare clyvo-oracle 2>/dev/null || true

if [[ "${1:-}" == "--purge" ]]; then
    docker volume rm clyvo-oracle-data 2>/dev/null || true
    docker network rm clyvo-net        2>/dev/null || true
    echo "Stack stopped and data volume purged."
else
    echo "Stack stopped. Data volume 'clyvo-oracle-data' preserved."
fi
