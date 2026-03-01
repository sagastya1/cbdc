#!/usr/bin/env bash
# Monitor CPU and memory usage of Besu containers during benchmark
# Usage: monitor_resources.sh <output_csv> [interval_seconds]
set -euo pipefail

OUTPUT_FILE="${1:-/results/resources.csv}"
INTERVAL="${2:-2}"

echo "timestamp,container,cpu_pct,mem_mb,mem_pct,net_rx_mb,net_tx_mb,block_read_mb,block_write_mb" > "$OUTPUT_FILE"

collect() {
    local ts
    ts=$(date +%s)
    
    # Docker stats: no-stream, all containers matching besu-poa or besu-qbft
    docker stats --no-stream --format \
        "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}}" \
        $(docker ps --format '{{.Names}}' | grep -E 'besu-(poa|qbft)' 2>/dev/null || echo "__NONE__") \
        2>/dev/null | while IFS=',' read -r name cpu mem_usage mem_pct net_io blk_io; do
            
            [[ "$name" == "__NONE__" ]] && continue
            
            # Parse memory (e.g. "512MiB / 16GiB")
            mem_mb=$(echo "$mem_usage" | awk '{gsub(/GiB/,"*1024");gsub(/MiB/,"");gsub(/kB/,"/1024");print $1}' | bc 2>/dev/null || echo "0")
            
            # Parse network I/O (e.g. "1.2MB / 3.4MB")
            net_rx=$(echo "$net_io" | awk -F'/' '{gsub(/[^0-9.]/,"",$1); print $1}')
            net_tx=$(echo "$net_io" | awk -F'/' '{gsub(/[^0-9.]/,"",$2); print $2}')
            
            # Parse block I/O
            blk_r=$(echo "$blk_io" | awk -F'/' '{gsub(/[^0-9.]/,"",$1); print $1}')
            blk_w=$(echo "$blk_io" | awk -F'/' '{gsub(/[^0-9.]/,"",$2); print $2}')
            
            cpu_clean="${cpu//%/}"
            
            echo "${ts},${name},${cpu_clean:-0},${mem_mb:-0},${mem_pct//%/},${net_rx:-0},${net_tx:-0},${blk_r:-0},${blk_w:-0}" >> "$OUTPUT_FILE"
        done
}

echo "[monitor] Collecting resource metrics every ${INTERVAL}s → ${OUTPUT_FILE}"
echo "[monitor] Press Ctrl+C to stop"

while true; do
    collect
    sleep "$INTERVAL"
done
