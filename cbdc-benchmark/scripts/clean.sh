#!/usr/bin/env bash
# Clean up all Docker resources and generated files
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Stopping all Besu containers..."
for consensus in poa qbft; do
    cd "${REPO_ROOT}/networks/${consensus}" 2>/dev/null || continue
    docker-compose down -v --remove-orphans 2>/dev/null || true
done

echo "Removing generated genesis/key files..."
for consensus in poa qbft; do
    rm -rf "${REPO_ROOT}/networks/${consensus}/data" \
           "${REPO_ROOT}/networks/${consensus}/keys" \
           "${REPO_ROOT}/networks/${consensus}/genesis.json" \
           "${REPO_ROOT}/networks/${consensus}/.env" \
           "${REPO_ROOT}/networks/${consensus}/qbft_extra.txt"
done

echo "Clearing results..."
rm -rf "${REPO_ROOT}/results"/*

echo "Removing Docker images (optional)..."
docker rmi hyperledger/besu:24.1.2 2>/dev/null || true

echo "Cleanup complete."
